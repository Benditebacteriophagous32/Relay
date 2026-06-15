package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.mau.fi/whatsmeow"
	waCommon "go.mau.fi/whatsmeow/proto/waCommon"
	waConsumerApplication "go.mau.fi/whatsmeow/proto/waConsumerApplication"
	waE2E "go.mau.fi/whatsmeow/proto/waE2E"
	waMediaTransport "go.mau.fi/whatsmeow/proto/waMediaTransport"
	waMsgApplication "go.mau.fi/whatsmeow/proto/waMsgApplication"
	"google.golang.org/protobuf/proto"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	_ "modernc.org/sqlite"
)

var (
	e2eeClient *whatsmeow.Client
	selfFBID   string
)

// setupE2EE connects the WhatsApp-protocol encrypted client that carries
// Messenger's E2EE (personal) chats. Registers a device once and persists it.
func setupE2EE(ctx context.Context, fbid int64) error {
	dir, _ := os.UserConfigDir()
	storeDir := filepath.Join(dir, "Relay")
	_ = os.MkdirAll(storeDir, 0o700)
	addr := "file:" + filepath.Join(storeDir, "wadevice.db") +
		"?_pragma=foreign_keys(1)&_pragma=busy_timeout(10000)"

	container, err := sqlstore.New(ctx, "sqlite", addr, waLog.Noop)
	if err != nil {
		return err
	}
	device, err := container.GetFirstDevice(ctx) // creates a fresh one if none
	if err != nil {
		return err
	}
	isNew := device.ID == nil
	if suggested := client.MessengerLite.GetSuggestedDeviceID(); suggested != uuid.Nil {
		device.FacebookUUID = suggested
	}
	client.SetDevice(device)

	if isNew {
		log.Info().Msg("registering new E2EE device (one-time)")
		if err := client.RegisterE2EE(ctx, fbid); err != nil {
			return err
		}
		if err := device.Save(ctx); err != nil {
			return err
		}
		log.Info().Msg("E2EE device registered")
	} else {
		log.Info().Msg("reusing saved E2EE device")
	}

	e2eeClient, err = client.PrepareE2EEClient()
	if err != nil {
		return err
	}
	// Reliability settings so encrypted messages aren't missed or lost:
	e2eeClient.EnableAutoReconnect = true                // heal transient socket drops
	e2eeClient.SynchronousAck = true                     // don't ack a message to the server…
	e2eeClient.EnableDecryptedEventBuffer = true         //   …until our handler has emitted it (no loss)
	e2eeClient.AutomaticMessageRerequestFromPhone = true // recover undecryptable messages from the phone

	e2eeClient.AddEventHandlerWithSuccessStatus(func(evt any) bool {
		switch e := evt.(type) {
		case *events.FBMessage: // Messenger E2EE messages (incl. offline + own-device)
			handleFBMessage(e)
		case *events.HistorySync:
			handleHistorySync(e)
		case *events.Presence: // online / last-seen
			handlePresence(e)
		case *events.ChatPresence: // typing indicator
			handleChatPresence(e)
		case *events.Receipt: // delivered / read
			handleReceipt(e)
		case *events.OfflineSyncPreview: // server is about to replay missed events
			log.Info().Int("messages", e.Messages).Int("total", e.Total).Msg("E2EE offline sync incoming")
		case *events.OfflineSyncCompleted:
			log.Info().Int("count", e.Count).Msg("E2EE offline sync completed")
		case *events.Connected:
			log.Info().Msg("E2EE socket connected")
			// Re-announce availability on every (re)connect — required to receive presence.
			_ = e2eeClient.SendPresence(context.Background(), types.PresenceAvailable)
		case *events.Disconnected:
			log.Warn().Msg("E2EE socket disconnected (auto-reconnecting)")
		case *events.LoggedOut:
			log.Error().Msg("E2EE logged out — session invalid")
			emit(map[string]any{"type": "error", "msg": "E2EE session expired — re-export cookies"})
		case *events.CATRefreshError: // auth token couldn't be refreshed in place
			log.Warn().Err(e.Error).Msg("E2EE auth token refresh failed — reloading session")
			go reloadE2EE()
		case *events.UndecryptableMessage:
			log.Warn().Str("chat", e.Info.Chat.User).Bool("unavailable", e.IsUnavailable).
				Msg("E2EE message failed to decrypt (auto-requesting resend)")
		default:
			log.Debug().Str("evt", fmt.Sprintf("%T", evt)).Msg("E2EE other event")
		}
		return true // we emit synchronously, so the message is safe to ack
	})
	if err := e2eeClient.Connect(); err != nil {
		return err
	}
	log.Info().Msg("✅ E2EE connected (encrypted personal chats)")
	return nil
}

// reloadE2EE refreshes the web session (which carries the encrypted client's auth
// token) and reconnects the encrypted socket — the recovery path when the token can't
// be refreshed in place, so the channel can't silently rot and start dropping messages.
// Cooldown-guarded so a burst of errors can't storm reloads.
var (
	e2eeReloadMu   sync.Mutex
	lastE2EEReload time.Time
)

func reloadE2EE() {
	e2eeReloadMu.Lock()
	defer e2eeReloadMu.Unlock()
	if !lastE2EEReload.IsZero() && time.Since(lastE2EEReload) < 30*time.Second {
		return
	}
	lastE2EEReload = time.Now()
	if _, _, err := client.LoadMessagesPage(context.Background()); err != nil {
		log.Warn().Err(err).Msg("session reload failed")
		return
	}
	if e2eeClient != nil {
		e2eeClient.Disconnect()
		if err := e2eeClient.Connect(); err != nil {
			log.Warn().Err(err).Msg("E2EE reconnect after reload failed")
		}
	}
	log.Info().Msg("E2EE session reloaded + reconnected")
}

var (
	subscribedPresence   = map[string]bool{}
	subscribedPresenceMu sync.Mutex
)

// subscribePresence starts receiving online/last-seen updates for one person.
// Tolerates being called before the E2EE socket is up (retries until it is).
func subscribePresence(fbid string) {
	if fbid == "" {
		return
	}
	subscribedPresenceMu.Lock()
	if subscribedPresence[fbid] {
		subscribedPresenceMu.Unlock()
		return
	}
	subscribedPresence[fbid] = true
	subscribedPresenceMu.Unlock()

	jid := types.JID{User: fbid, Server: types.MessengerServer}
	for i := 0; i < 15; i++ {
		if e2eeClient != nil {
			if err := e2eeClient.SubscribePresence(context.Background(), jid); err == nil {
				return
			}
		}
		time.Sleep(2 * time.Second)
	}
	subscribedPresenceMu.Lock()
	delete(subscribedPresence, fbid)
	subscribedPresenceMu.Unlock()
}

func handlePresence(e *events.Presence) {
	if e.From.User == "" {
		return
	}
	out := map[string]any{"type": "presence", "id": e.From.User, "online": !e.Unavailable}
	if !e.LastSeen.IsZero() {
		out["lastSeen"] = float64(e.LastSeen.UnixMilli())
	}
	emit(out)
}

func handleChatPresence(e *events.ChatPresence) {
	emit(map[string]any{
		"type": "typing", "thread": "e:" + e.Chat.User, "id": e.Sender.User,
		"composing": e.State == types.ChatPresenceComposing,
	})
}

// handleReceipt surfaces delivered/read receipts for our sent encrypted messages as a
// per-thread watermark timestamp (Messenger shows one "Seen"/"Delivered" under the last).
func handleReceipt(e *events.Receipt) {
	var status string
	switch e.Type {
	case types.ReceiptTypeRead, types.ReceiptTypeReadSelf:
		status = "read"
	case types.ReceiptTypeDelivered:
		status = "delivered"
	default:
		return
	}
	if e.Chat.User == "" {
		return
	}
	emit(map[string]any{
		"type": "receipt", "thread": "e:" + e.Chat.User,
		"status": status, "ts": float64(e.Timestamp.UnixMilli()),
	})
}

// markE2EERead tells the server we've read up to a message (so the other side sees "Seen").
func markE2EERead(fbid, msgID, sender string, tsMs int64) {
	if e2eeClient == nil || msgID == "" {
		return
	}
	chat := types.JID{User: fbid, Server: types.MessengerServer}
	snd := types.JID{User: sender, Server: types.MessengerServer}
	t := time.UnixMilli(tsMs)
	if tsMs == 0 {
		t = time.Now()
	}
	if err := e2eeClient.MarkRead(context.Background(), []string{msgID}, t, chat, snd); err != nil {
		log.Debug().Err(err).Msg("E2EE mark read failed")
	}
}

// sendE2EEReaction adds (emoji) or removes (empty) a reaction on an encrypted message.
func sendE2EEReaction(fbid, targetMsgID, emoji string, targetFromMe bool) error {
	if e2eeClient == nil {
		return fmt.Errorf("E2EE not connected yet")
	}
	chat := types.JID{User: fbid, Server: types.MessengerServer}
	rm := &waConsumerApplication.ConsumerApplication_ReactionMessage{
		Key: &waCommon.MessageKey{
			RemoteJID: proto.String(chat.String()),
			FromMe:    proto.Bool(targetFromMe),
			ID:        proto.String(targetMsgID),
		},
		Text:              proto.String(emoji),
		SenderTimestampMS: proto.Int64(time.Now().UnixMilli()),
	}
	app := &waConsumerApplication.ConsumerApplication{
		Payload: &waConsumerApplication.ConsumerApplication_Payload{
			Payload: &waConsumerApplication.ConsumerApplication_Payload_Content{
				Content: &waConsumerApplication.ConsumerApplication_Content{
					Content: &waConsumerApplication.ConsumerApplication_Content_ReactionMessage{ReactionMessage: rm},
				},
			},
		},
	}
	_, err := e2eeClient.SendFBMessage(context.Background(), chat, app, nil, whatsmeow.SendRequestExtra{})
	return err
}

// sendE2EE sends a text message to an encrypted Messenger thread (optionally a reply).
func sendE2EE(fbid, text, replyID, replySender, clientTag string) {
	if e2eeClient == nil {
		emit(map[string]any{"type": "error", "msg": "E2EE not connected yet"})
		return
	}
	jid := types.JID{User: fbid, Server: types.MessengerServer}
	msg := &waConsumerApplication.ConsumerApplication{
		Payload: &waConsumerApplication.ConsumerApplication_Payload{
			Payload: &waConsumerApplication.ConsumerApplication_Payload_Content{
				Content: &waConsumerApplication.ConsumerApplication_Content{
					Content: &waConsumerApplication.ConsumerApplication_Content_MessageText{
						MessageText: &waCommon.MessageText{Text: proto.String(text)},
					},
				},
			},
		},
	}
	var meta *waMsgApplication.MessageApplication_Metadata
	if replyID != "" {
		sender := replySender
		if sender == "" {
			sender = fbid
		}
		meta = &waMsgApplication.MessageApplication_Metadata{
			QuotedMessage: &waMsgApplication.MessageApplication_Metadata_QuotedMessage{
				StanzaID:    proto.String(replyID),
				Participant: proto.String(types.JID{User: sender, Server: types.MessengerServer}.String()),
			},
		}
	}
	resp, err := e2eeClient.SendFBMessage(context.Background(), jid, msg, meta, whatsmeow.SendRequestExtra{})
	if err != nil {
		log.Warn().Err(err).Msg("E2EE send failed")
		emit(map[string]any{"type": "error", "msg": "E2EE send: " + err.Error()})
		return
	}
	// Encrypted sends aren't echoed back to us by the server, so the app shows an
	// optimistic bubble under a temporary id. Hand back the REAL message id (keyed by
	// the app's clientTag) so it can swap it in — otherwise incoming reactions/edits,
	// which target the real id, would never match the bubble.
	if clientTag != "" && resp.ID != "" {
		emit(map[string]any{"type": "sent", "clientTag": clientTag, "id": resp.ID, "thread": "e:" + fbid})
	}
}

// sendE2EEMedia uploads + encrypts any media (picture/video/voice/file) and sends it,
// built the way the Messenger apps expect (the Thumbnail dimensions are required for
// images or iOS/Android refuse to display them).
func sendE2EEMedia(fbid, kind string, data []byte, mime, caption, fileName string, w, h int) error {
	if e2eeClient == nil {
		return fmt.Errorf("E2EE not connected yet")
	}
	var mediaType whatsmeow.MediaType
	switch kind {
	case "image":
		mediaType = whatsmeow.MediaImage
	case "video":
		mediaType = whatsmeow.MediaVideo
	case "audio":
		mediaType = whatsmeow.MediaAudio
	default:
		mediaType = whatsmeow.MediaDocument
	}
	uploaded, err := e2eeClient.Upload(context.Background(), data, mediaType)
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	if w == 0 {
		w, h = 400, 400
	}
	mt := &waMediaTransport.WAMediaTransport{
		Integral: &waMediaTransport.WAMediaTransport_Integral{
			FileSHA256:        uploaded.FileSHA256,
			MediaKey:          uploaded.MediaKey,
			FileEncSHA256:     uploaded.FileEncSHA256,
			DirectPath:        &uploaded.DirectPath,
			MediaKeyTimestamp: proto.Int64(time.Now().Unix()),
		},
		Ancillary: &waMediaTransport.WAMediaTransport_Ancillary{
			FileLength: proto.Uint64(uint64(len(data))),
			Mimetype:   &mime,
			Thumbnail: &waMediaTransport.WAMediaTransport_Ancillary_Thumbnail{
				ThumbnailWidth:  proto.Uint32(uint32(w)),
				ThumbnailHeight: proto.Uint32(uint32(h)),
			},
			ObjectID: &uploaded.ObjectID,
		},
	}
	var cap *waCommon.MessageText
	if caption != "" {
		cap = &waCommon.MessageText{Text: proto.String(caption)}
	}
	var content waConsumerApplication.ConsumerApplication_Content_Content
	switch kind {
	case "video":
		m := &waConsumerApplication.ConsumerApplication_VideoMessage{Caption: cap}
		if err := m.Set(&waMediaTransport.VideoTransport{
			Integral:  &waMediaTransport.VideoTransport_Integral{Transport: mt},
			Ancillary: &waMediaTransport.VideoTransport_Ancillary{Height: proto.Uint32(uint32(h)), Width: proto.Uint32(uint32(w))},
		}); err != nil {
			return err
		}
		content = &waConsumerApplication.ConsumerApplication_Content_VideoMessage{VideoMessage: m}
	case "audio":
		ptt := true // treat sent audio as a voice note
		m := &waConsumerApplication.ConsumerApplication_AudioMessage{PTT: &ptt}
		if err := m.Set(&waMediaTransport.AudioTransport{
			Integral:  &waMediaTransport.AudioTransport_Integral{Transport: mt},
			Ancillary: &waMediaTransport.AudioTransport_Ancillary{},
		}); err != nil {
			return err
		}
		content = &waConsumerApplication.ConsumerApplication_Content_AudioMessage{AudioMessage: m}
	case "file":
		fn := fileName
		m := &waConsumerApplication.ConsumerApplication_DocumentMessage{FileName: &fn}
		if err := m.Set(&waMediaTransport.DocumentTransport{
			Integral:  &waMediaTransport.DocumentTransport_Integral{Transport: mt},
			Ancillary: &waMediaTransport.DocumentTransport_Ancillary{},
		}); err != nil {
			return err
		}
		content = &waConsumerApplication.ConsumerApplication_Content_DocumentMessage{DocumentMessage: m}
	default:
		m := &waConsumerApplication.ConsumerApplication_ImageMessage{Caption: cap}
		if err := m.Set(&waMediaTransport.ImageTransport{
			Integral:  &waMediaTransport.ImageTransport_Integral{Transport: mt},
			Ancillary: &waMediaTransport.ImageTransport_Ancillary{Height: proto.Uint32(uint32(h)), Width: proto.Uint32(uint32(w))},
		}); err != nil {
			return err
		}
		content = &waConsumerApplication.ConsumerApplication_Content_ImageMessage{ImageMessage: m}
	}
	app := &waConsumerApplication.ConsumerApplication{
		Payload: &waConsumerApplication.ConsumerApplication_Payload{
			Payload: &waConsumerApplication.ConsumerApplication_Payload_Content{
				Content: &waConsumerApplication.ConsumerApplication_Content{Content: content},
			},
		},
	}
	jid := types.JID{User: fbid, Server: types.MessengerServer}
	_, err = e2eeClient.SendFBMessage(context.Background(), jid, app, nil, whatsmeow.SendRequestExtra{})
	return err
}

// sendE2EEEdit changes the text of one of our already-sent encrypted messages.
func sendE2EEEdit(fbid, msgID, text string) error {
	if e2eeClient == nil {
		return fmt.Errorf("E2EE not connected yet")
	}
	chat := types.JID{User: fbid, Server: types.MessengerServer}
	em := &waConsumerApplication.ConsumerApplication_EditMessage{
		Key: &waCommon.MessageKey{
			RemoteJID: proto.String(chat.String()),
			FromMe:    proto.Bool(true),
			ID:        proto.String(msgID),
		},
		Message: &waCommon.MessageText{Text: proto.String(text)},
	}
	app := &waConsumerApplication.ConsumerApplication{
		Payload: &waConsumerApplication.ConsumerApplication_Payload{
			Payload: &waConsumerApplication.ConsumerApplication_Payload_Content{
				Content: &waConsumerApplication.ConsumerApplication_Content{
					Content: &waConsumerApplication.ConsumerApplication_Content_EditMessage{EditMessage: em},
				},
			},
		},
	}
	_, err := e2eeClient.SendFBMessage(context.Background(), chat, app, nil, whatsmeow.SendRequestExtra{})
	return err
}

// sendE2EEUnsend revokes (deletes for everyone) one of our encrypted messages.
func sendE2EEUnsend(fbid, msgID string) error {
	if e2eeClient == nil {
		return fmt.Errorf("E2EE not connected yet")
	}
	chat := types.JID{User: fbid, Server: types.MessengerServer}
	app := &waConsumerApplication.ConsumerApplication{
		Payload: &waConsumerApplication.ConsumerApplication_Payload{
			Payload: &waConsumerApplication.ConsumerApplication_Payload_ApplicationData{
				ApplicationData: &waConsumerApplication.ConsumerApplication_ApplicationData{
					ApplicationContent: &waConsumerApplication.ConsumerApplication_ApplicationData_Revoke{
						Revoke: &waConsumerApplication.ConsumerApplication_RevokeMessage{
							Key: &waCommon.MessageKey{
								RemoteJID: proto.String(chat.String()),
								FromMe:    proto.Bool(true),
								ID:        proto.String(msgID),
							},
						},
					},
				},
			},
		},
	}
	_, err := e2eeClient.SendFBMessage(context.Background(), chat, app, nil, whatsmeow.SendRequestExtra{})
	return err
}

func msgText(m *waE2E.Message) string {
	if m == nil {
		return ""
	}
	if t := m.GetConversation(); t != "" {
		return t
	}
	if e := m.GetExtendedTextMessage(); e != nil {
		return e.GetText()
	}
	return ""
}

// Text (or a typed placeholder) from a Messenger E2EE (armadillo ConsumerApplication)
// message. Non-text content is rendered as a labelled placeholder so photos, voice
// notes, stickers etc. never silently vanish from the conversation. Reactions/edits
// are NOT messages and return "" here (handled separately).
func fbText(e *events.FBMessage) string {
	content := e.GetConsumerApplication().GetPayload().GetContent()
	switch c := content.GetContent().(type) {
	case *waConsumerApplication.ConsumerApplication_Content_MessageText:
		return c.MessageText.GetText()
	case *waConsumerApplication.ConsumerApplication_Content_ExtendedTextMessage:
		return c.ExtendedTextMessage.GetText().GetText()
	case *waConsumerApplication.ConsumerApplication_Content_ImageMessage:
		return "📷 Photo"
	case *waConsumerApplication.ConsumerApplication_Content_VideoMessage:
		return "🎬 Video"
	case *waConsumerApplication.ConsumerApplication_Content_AudioMessage:
		return "🎤 Voice message"
	case *waConsumerApplication.ConsumerApplication_Content_StickerMessage:
		return "💟 Sticker"
	case *waConsumerApplication.ConsumerApplication_Content_DocumentMessage:
		return "📎 File"
	case *waConsumerApplication.ConsumerApplication_Content_LocationMessage,
		*waConsumerApplication.ConsumerApplication_Content_LiveLocationMessage:
		return "📍 Location"
	case *waConsumerApplication.ConsumerApplication_Content_ContactMessage,
		*waConsumerApplication.ConsumerApplication_Content_ContactsArrayMessage:
		return "👤 Contact"
	}
	return ""
}

// mediaDownloader returns a kind label + a function that downloads & decrypts the
// media for an encrypted message, if it carries any. nil func = no media.
func mediaDownloader(e *events.FBMessage) (kind string, dl func() ([]byte, string, error)) {
	content := e.GetConsumerApplication().GetPayload().GetContent()
	switch c := content.GetContent().(type) {
	case *waConsumerApplication.ConsumerApplication_Content_ImageMessage:
		return "image", func() ([]byte, string, error) {
			t, err := c.ImageMessage.Decode()
			if err != nil {
				return nil, "", err
			}
			data, err := e2eeClient.DownloadFB(context.Background(), t.GetIntegral().GetTransport().GetIntegral(), whatsmeow.MediaImage)
			return data, "jpg", err
		}
	case *waConsumerApplication.ConsumerApplication_Content_StickerMessage:
		return "sticker", func() ([]byte, string, error) {
			t, err := c.StickerMessage.Decode()
			if err != nil {
				return nil, "", err
			}
			data, err := e2eeClient.DownloadFB(context.Background(), t.GetIntegral().GetTransport().GetIntegral(), whatsmeow.MediaImage)
			return data, "webp", err
		}
	case *waConsumerApplication.ConsumerApplication_Content_VideoMessage:
		return "video", func() ([]byte, string, error) {
			t, err := c.VideoMessage.Decode()
			if err != nil {
				return nil, "", err
			}
			data, err := e2eeClient.DownloadFB(context.Background(), t.GetIntegral().GetTransport().GetIntegral(), whatsmeow.MediaVideo)
			return data, "mp4", err
		}
	case *waConsumerApplication.ConsumerApplication_Content_AudioMessage:
		return "audio", func() ([]byte, string, error) {
			t, err := c.AudioMessage.Decode()
			if err != nil {
				return nil, "", err
			}
			data, err := e2eeClient.DownloadFB(context.Background(), t.GetIntegral().GetTransport().GetIntegral(), whatsmeow.MediaAudio)
			return data, "m4a", err
		}
	case *waConsumerApplication.ConsumerApplication_Content_DocumentMessage:
		return "file", func() ([]byte, string, error) {
			t, err := c.DocumentMessage.Decode()
			if err != nil {
				return nil, "", err
			}
			data, err := e2eeClient.DownloadFB(context.Background(), t.GetIntegral().GetTransport().GetIntegral(), whatsmeow.MediaDocument)
			ext := "bin"
			if fn := c.DocumentMessage.GetFileName(); fn != "" {
				if i := strings.LastIndex(fn, "."); i >= 0 && i < len(fn)-1 {
					ext = fn[i+1:]
				}
			}
			return data, ext, err
		}
	}
	return "", nil
}

// saveMedia writes downloaded media to the app's media cache and returns its path.
func saveMedia(id, ext string, data []byte) string {
	dir, _ := os.UserConfigDir()
	mdir := filepath.Join(dir, "Relay", "media")
	_ = os.MkdirAll(mdir, 0o700)
	safe := strings.NewReplacer("/", "_", ":", "_", "$", "_", ".", "_").Replace(id)
	p := filepath.Join(mdir, safe+"."+ext)
	if err := os.WriteFile(p, data, 0o600); err != nil {
		log.Warn().Err(err).Msg("save media failed")
		return ""
	}
	return p
}

func handleFBMessage(e *events.FBMessage) {
	if e.Info.Chat.User == "" {
		return
	}
	// Unsend / delete: the partner (or you, from another device) removed a message.
	if rev := e.GetConsumerApplication().GetPayload().GetApplicationData().GetRevoke(); rev != nil {
		if id := rev.GetKey().GetID(); id != "" {
			emit(map[string]any{"type": "delete", "thread": "e:" + e.Info.Chat.User, "id": id})
		}
		return
	}
	// Reaction add (emoji) / remove (empty) on one of our (or their) messages.
	if c, ok := e.GetConsumerApplication().GetPayload().GetContent().GetContent().(*waConsumerApplication.ConsumerApplication_Content_ReactionMessage); ok {
		rm := c.ReactionMessage
		emit(map[string]any{
			"type": "reaction", "thread": "e:" + e.Info.Chat.User,
			"id": rm.GetKey().GetID(), "emoji": rm.GetText(), "actor": e.Info.Sender.User,
		})
		return
	}
	// Edit: the author changed a sent message's text.
	if c, ok := e.GetConsumerApplication().GetPayload().GetContent().GetContent().(*waConsumerApplication.ConsumerApplication_Content_EditMessage); ok {
		if id := c.EditMessage.GetKey().GetID(); id != "" {
			emit(map[string]any{
				"type": "edit", "thread": "e:" + e.Info.Chat.User,
				"id": id, "text": c.EditMessage.GetMessage().GetText(),
			})
		}
		return
	}
	text := fbText(e)
	log.Info().Str("chat", e.Info.Chat.User).Bool("fromMe", e.Info.IsFromMe).
		Str("text", text).Msg("⟵ E2EE FBMessage")
	if text == "" {
		return
	}
	thread := "e:" + e.Info.Chat.User // namespaced so E2EE rows never collide with non-E2EE
	sender := e.Info.Sender.User
	ts := float64(e.Info.Timestamp.UnixMilli())
	isGroup := e.Info.Chat.Server == types.GroupServer

	name := ""
	if !isGroup && !e.Info.IsFromMe && e.Info.PushName != "" && e.Info.PushName != "username" {
		name = e.Info.PushName
	}
	// Resolve the partner's real name + avatar — encrypted contacts are never in
	// the normal sync, so this is the only way their chat gets a name and picture.
	if !isGroup {
		if fbid, err := strconv.ParseInt(e.Info.Chat.User, 10, 64); err == nil {
			go fetchContact(fbid)
			markE2EEKey(fbid) // backfill for this chat should merge into the encrypted thread
		}
		go subscribePresence(e.Info.Chat.User)
	}
	emit(map[string]any{
		"type": "thread", "id": thread, "contact": e.Info.Chat.User, "name": name,
		"snippet": text, "lastActivity": ts, "unread": !e.Info.IsFromMe, "e2ee": true,
	})
	msgEv := map[string]any{
		"type": "message", "id": e.Info.ID, "thread": thread, "sender": sender,
		"text": text, "ts": ts, "live": true, "system": false,
	}
	// Reply: carry the quoted message's id + author (the app fills in the quoted
	// text from its local copy). The quote lives in the message-application metadata.
	if e.FBApplication != nil {
		if q := e.FBApplication.GetMetadata().GetQuotedMessage(); q != nil {
			if sid := q.GetStanzaID(); sid != "" {
				msgEv["replyToId"] = sid
				if p := q.GetParticipant(); p != "" {
					msgEv["replyToSender"] = strings.SplitN(p, "@", 2)[0]
				}
			}
		}
	}
	emit(msgEv)

	// Download + decrypt any picture/sticker so it renders inline (not just as text).
	if kind, dl := mediaDownloader(e); dl != nil {
		msgID, th := e.Info.ID, thread
		go func() {
			data, ext, err := dl()
			if err != nil || len(data) == 0 {
				log.Warn().Err(err).Str("kind", kind).Msg("media download failed")
				return
			}
			if p := saveMedia(msgID, ext, data); p != "" {
				emit(map[string]any{"type": "media", "id": msgID, "thread": th, "kind": kind, "path": p})
			}
		}()
	}
}

// Backfill: the phone sends recent encrypted history when a device registers.
func handleHistorySync(e *events.HistorySync) {
	if e.Data == nil {
		return
	}
	for _, conv := range e.Data.GetConversations() {
		jid := conv.GetID()
		raw := strings.SplitN(jid, "@", 2)[0]
		if raw == "" {
			continue
		}
		thread := "e:" + raw
		isGroup := strings.Contains(jid, "@g.us")
		var name, lastText string
		var lastTs float64
		for _, hm := range conv.GetMessages() {
			wmi := hm.GetMessage()
			if wmi == nil {
				continue
			}
			text := msgText(wmi.GetMessage())
			if text == "" {
				continue
			}
			key := wmi.GetKey()
			sender := raw
			if isGroup {
				sender = strings.SplitN(key.GetParticipant(), "@", 2)[0]
			}
			if key.GetFromMe() {
				sender = selfFBID
			} else if !isGroup && wmi.GetPushName() != "" {
				name = wmi.GetPushName()
			}
			ts := float64(wmi.GetMessageTimestamp()) * 1000
			emit(map[string]any{
				"type": "message", "id": key.GetID(), "thread": thread, "sender": sender,
				"text": text, "ts": ts, "live": false, "system": false,
			})
			lastText, lastTs = text, ts
		}
		if lastText != "" {
			emit(map[string]any{
				"type": "thread", "id": thread, "contact": raw, "name": name,
				"snippet": lastText, "lastActivity": lastTs, "unread": false, "e2ee": true,
			})
		}
	}
}
