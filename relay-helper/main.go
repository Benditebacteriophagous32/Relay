// relay-helper — Relay's backend daemon.
//
// Embeds messagix (Meta's reverse-engineered protocol) and exposes a tiny,
// stable JSON-over-stdio API for the SwiftUI app:
//
//   stdin  (commands, one JSON object per line):
//     {"cmd":"login","cookies":"datr=…; c_user=…; xs=…"}
//     {"cmd":"send","thread":123,"text":"hello"}
//
//   stdout (events, one JSON object per line):
//     {"type":"ready","self":123}
//     {"type":"contact","id":1,"name":"…","firstName":"…","avatar":"…"}
//     {"type":"thread","id":1,"name":"…","snippet":"…","lastActivity":…,"unread":true}
//     {"type":"message","id":"…","thread":1,"sender":1,"text":"…","ts":…,"live":true}
//     {"type":"error","msg":"…"}
//
// All logging goes to STDERR so stdout stays a clean protocol stream.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog"
	"go.mau.fi/mautrix-meta/pkg/messagix"
	"go.mau.fi/mautrix-meta/pkg/messagix/cookies"
	"go.mau.fi/mautrix-meta/pkg/messagix/methods"
	"go.mau.fi/mautrix-meta/pkg/messagix/socket"
	"go.mau.fi/mautrix-meta/pkg/messagix/table"
	"go.mau.fi/mautrix-meta/pkg/messagix/types"
)

var (
	log    zerolog.Logger
	outMu  sync.Mutex
	client *messagix.Client
)

func emit(obj map[string]any) {
	outMu.Lock()
	defer outMu.Unlock()
	b, err := json.Marshal(obj)
	if err != nil {
		return
	}
	os.Stdout.Write(b)
	os.Stdout.Write([]byte("\n"))
}

func main() {
	log = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: "15:04:05"}).With().Timestamp().Logger()

	// Read commands from stdin in the background.
	cmds := make(chan map[string]any, 16)
	go func() {
		sc := bufio.NewScanner(os.Stdin)
		sc.Buffer(make([]byte, 1024*1024), 8*1024*1024)
		for sc.Scan() {
			line := strings.TrimSpace(sc.Text())
			if line == "" {
				continue
			}
			var m map[string]any
			if err := json.Unmarshal([]byte(line), &m); err != nil {
				log.Warn().Err(err).Msg("bad command")
				continue
			}
			cmds <- m
		}
		os.Exit(0) // stdin closed → app quit
	}()

	// First command must be login (or a --cookies file arg for CLI testing).
	var cookieStr string
	if len(os.Args) > 1 {
		if raw, err := os.ReadFile(os.Args[1]); err == nil {
			cookieStr = strings.TrimSpace(string(raw))
		}
	}
	for cookieStr == "" {
		m := <-cmds
		if m["cmd"] == "login" {
			cookieStr, _ = m["cookies"].(string)
		}
	}

	if err := connect(cookieStr); err != nil {
		emit(map[string]any{"type": "error", "msg": err.Error()})
		log.Fatal().Err(err).Msg("connect failed")
	}

	// Serve commands.
	for m := range cmds {
		switch m["cmd"] {
		case "send":
			thread, _ := m["thread"].(string)
			text, _ := m["text"].(string)
			replyID, _ := m["replyId"].(string)
			replySender, _ := m["replySender"].(string)
			clientTag, _ := m["clientTag"].(string)
			if thread != "" && text != "" {
				go sendMessage(thread, text, replyID, replySender, clientTag)
			}
		case "fetchContact":
			// App asks us to resolve a person it knows by FBID but has no name/avatar for.
			if id := toInt64(m["id"]); id != 0 {
				go fetchContact(id)
			}
		case "sendMedia":
			thread, _ := m["thread"].(string)
			path, _ := m["path"].(string)
			caption, _ := m["caption"].(string)
			if thread != "" && path != "" {
				go sendMediaMessage(thread, path, caption)
			}
		case "sendGif":
			thread, _ := m["thread"].(string)
			url, _ := m["url"].(string)
			if thread != "" && url != "" {
				go sendGif(thread, url)
			}
		case "refreshThread":
			// App opened a thread — pull anything newer than what it has.
			if thread, _ := m["thread"].(string); thread != "" {
				go refreshThread(thread)
			}
		case "react":
			thread, _ := m["thread"].(string)
			id, _ := m["id"].(string)
			emoji, _ := m["emoji"].(string)
			fromMe, _ := m["fromMe"].(bool)
			if thread != "" && id != "" {
				go sendReaction(thread, id, emoji, fromMe)
			}
		case "unsend":
			thread, _ := m["thread"].(string)
			id, _ := m["id"].(string)
			if thread != "" && id != "" {
				go unsendMessage(thread, id)
			}
		case "edit":
			thread, _ := m["thread"].(string)
			id, _ := m["id"].(string)
			text, _ := m["text"].(string)
			if thread != "" && id != "" && text != "" {
				go editMessage(thread, id, text)
			}
		case "markReadServer":
			thread, _ := m["thread"].(string)
			id, _ := m["id"].(string)
			sender, _ := m["sender"].(string)
			ts := toInt64(m["ts"])
			if thread != "" {
				go markReadServer(thread, id, sender, ts)
			}
		case "mute":
			thread, _ := m["thread"].(string)
			muted, _ := m["muted"].(bool)
			if thread != "" {
				go setMute(thread, muted)
			}
		case "deleteThread":
			if thread, _ := m["thread"].(string); thread != "" {
				go deleteThread(thread)
			}
		case "renameThread":
			thread, _ := m["thread"].(string)
			name, _ := m["name"].(string)
			if thread != "" {
				go renameThread(thread, name)
			}
		case "addMembers":
			if thread, _ := m["thread"].(string); thread != "" {
				go addMembers(thread, m["ids"])
			}
		case "removeMember":
			thread, _ := m["thread"].(string)
			id, _ := m["id"].(string)
			if thread != "" && id != "" {
				go removeMember(thread, id)
			}
		case "setAdmin":
			thread, _ := m["thread"].(string)
			id, _ := m["id"].(string)
			admin, _ := m["admin"].(bool)
			if thread != "" && id != "" {
				go setThreadAdmin(thread, id, admin)
			}
		case "leaveThread":
			if thread, _ := m["thread"].(string); thread != "" {
				go leaveThread(thread)
			}
		case "setGroupPhoto":
			thread, _ := m["thread"].(string)
			path, _ := m["path"].(string)
			if thread != "" && path != "" {
				go setGroupPhoto(thread, path)
			}
		case "createGroup":
			name, _ := m["name"].(string)
			go createGroup(name, m["ids"])
		case "subscribePresence":
			// App asks us to watch a person's online / last-seen status (E2EE contacts).
			if id, _ := m["id"].(string); id != "" {
				go subscribePresence(id)
			}
		case "loadEarlier":
			// App asks for older messages before the oldest one it has in a thread.
			thread, _ := m["thread"].(string)
			oldestID, _ := m["oldestId"].(string)
			oldestTs := toInt64(m["oldestTs"])
			fromMe, _ := m["fromMe"].(bool)
			if thread != "" {
				go loadEarlier(thread, oldestID, oldestTs, fromMe)
			}
		}
	}
}

func connect(cookieStr string) error {
	c := &cookies.Cookies{Platform: types.Messenger}
	vals := map[cookies.MetaCookieName]string{}
	for _, part := range strings.Split(cookieStr, ";") {
		kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(kv) == 2 {
			vals[cookies.MetaCookieName(kv[0])] = kv[1]
		}
	}
	c.UpdateValues(vals)
	log.Info().Int64("user", c.GetUserID()).Bool("loggedin", c.IsLoggedIn()).Msg("cookies")

	// No valid session → tell the app to show the in-app login.
	if !c.IsLoggedIn() {
		emit(map[string]any{"type": "needLogin"})
		return errors.New("not logged in: no valid session cookies")
	}

	client = messagix.NewClient(c, log, &messagix.Config{})
	client.SetEventHandler(func(ctx context.Context, evt any) {
		switch e := evt.(type) {
		case *messagix.Event_Ready:
			emit(map[string]any{"type": "ready", "self": fmtID(c.GetUserID())})
		case *messagix.Event_PublishResponse:
			if e.Table != nil {
				processTable(e.Table, true)
			}
		}
	})

	ctx := context.Background()
	user, tbl, err := client.LoadMessagesPage(ctx)
	if err != nil {
		return err
	}
	selfFBID = fmtID(c.GetUserID())
	emit(map[string]any{"type": "self", "id": selfFBID, "name": user.GetName()})
	if tbl != nil {
		processTable(tbl, false)
	}
	if err := client.Connect(ctx); err != nil {
		return err
	}
	emit(map[string]any{"type": "ready", "self": selfFBID})

	// Connect the encrypted (E2EE / WhatsApp-protocol) channel for personal chats.
	go func() {
		if err := setupE2EE(context.Background(), c.GetUserID()); err != nil {
			log.Warn().Err(err).Msg("E2EE setup failed")
			emit(map[string]any{"type": "error", "msg": "E2EE: " + err.Error()})
		}
	}()
	return nil
}

// Thread keys we know are encrypted (E2EE 1:1). Backfill for these comes back on the
// normal publish stream with the RAW key, but the UI tracks them as "e:<key>", so we
// re-namespace their messages/threads to merge with the live encrypted thread.
var e2eeKeys sync.Map // int64 → true

func markE2EEKey(tid int64) {
	if tid != 0 {
		e2eeKeys.Store(tid, true)
	}
}
func isE2EEKey(tid int64) bool { _, ok := e2eeKeys.Load(tid); return ok }
func emitThreadID(tid int64) string {
	if isE2EEKey(tid) {
		return "e:" + fmtID(tid)
	}
	return fmtID(tid)
}

// normalizeFolder maps Meta's many folder names (incl. the "e2ee_cutover_*"
// variants for encrypted threads) onto the four buckets the inbox shows.
func normalizeFolder(name string) string {
	switch {
	case strings.Contains(name, "pending"), strings.Contains(name, "other"):
		return "requests"
	case strings.Contains(name, "spam"):
		return "spam"
	case strings.Contains(name, "archived"):
		return "archived"
	case name == "montage" || name == "hidden" || name == "disabled" || name == "blocked":
		return "hidden"
	default:
		return "inbox"
	}
}

func attachTypeLabel(t table.AttachmentType) string {
	switch t {
	case table.AttachmentTypeImage, table.AttachmentTypeAnimatedImage:
		return "📷 Photo"
	case table.AttachmentTypeVideo:
		return "🎬 Video"
	case table.AttachmentTypeAudio:
		return "🎤 Voice message"
	case table.AttachmentTypeSticker:
		return "💟 Sticker"
	case table.AttachmentTypeFile:
		return "📎 File"
	default:
		return "📎 Attachment"
	}
}

func processTable(tbl *table.LSTable, live bool) {
	emitContact := func(id int64, name, first, avatar string) {
		if id == 0 {
			return
		}
		emit(map[string]any{
			"type": "contact", "id": fmtID(id), "name": name,
			"firstName": first, "avatar": avatar,
		})
	}
	// Contact info arrives via either struct depending on the sync.
	for _, ct := range tbl.LSDeleteThenInsertContact {
		emitContact(ct.Id, ct.Name, ct.FirstName, ct.ProfilePictureUrl)
	}
	for _, ct := range tbl.LSVerifyContactRowExists {
		emitContact(ct.ContactId, ct.Name, ct.FirstName, ct.ProfilePictureUrl)
	}
	// Thread → participant links, so the app can name/illustrate 1:1 threads.
	for _, p := range tbl.LSAddParticipantIdToGroupThread {
		emit(map[string]any{
			"type": "participant", "thread": fmtID(p.ThreadKey),
			"contact": fmtID(p.ContactId), "nickname": p.Nickname,
			"admin": p.IsAdmin || p.IsSuperAdmin,
		})
	}
	// Admin promotions/demotions.
	for _, a := range tbl.LSUpdateThreadParticipantAdminStatus {
		emit(map[string]any{
			"type": "admin", "thread": fmtID(a.ThreadKey),
			"contact": fmtID(a.ContactId), "admin": a.IsAdmin,
		})
	}
	// Online / last-seen — Messenger active status comes through the Lightspeed channel
	// (NOT whatsmeow presence). Someone is "active now" while their status hasn't expired.
	now := time.Now().UnixMilli()
	if n := len(tbl.LSDeleteThenInsertContactPresence); n > 0 || len(tbl.LSTruncatePresenceDatabase) > 0 {
		log.Info().Int("presence_rows", n).Int("truncate", len(tbl.LSTruncatePresenceDatabase)).
			Bool("live", live).Msg("PRESENCE table received")
	}
	for _, p := range tbl.LSDeleteThenInsertContactPresence {
		if p.ContactId == 0 {
			continue
		}
		online := p.ExpirationTimestampMs > now
		ev := map[string]any{
			"type": "presence", "id": fmtID(p.ContactId),
			"online": online,
		}
		if p.LastActiveTimestampMs > 0 {
			ev["lastSeen"] = float64(p.LastActiveTimestampMs)
		}
		log.Info().Str("id", fmtID(p.ContactId)).Bool("online", online).
			Int64("status", p.Status).Int64("lastActive", p.LastActiveTimestampMs).
			Int64("expires", p.ExpirationTimestampMs).Msg("PRESENCE row")
		emit(ev)
	}
	// Unsend / delete in regular chats — remove the message from the UI.
	for _, d := range tbl.LSDeleteMessage {
		if d.MessageId != "" {
			emit(map[string]any{"type": "delete", "thread": emitThreadID(d.ThreadKey), "id": d.MessageId})
		}
	}
	// Edited messages — update the text in place.
	for _, ed := range tbl.LSEditMessage {
		if ed.MessageID != "" {
			emit(map[string]any{"type": "edit", "id": ed.MessageID, "text": ed.Text})
		}
	}
	// Read receipts (regular chats) — per-thread "read up to" watermark.
	for _, r := range tbl.LSUpdateReadReceipt {
		emit(map[string]any{
			"type": "receipt", "thread": emitThreadID(r.ThreadKey),
			"status": "read", "ts": float64(r.ReadWatermarkTimestampMs),
		})
	}
	// Reactions (regular chats): upsert = add/change, delete = remove.
	for _, r := range tbl.LSUpsertReaction {
		emit(map[string]any{
			"type": "reaction", "thread": emitThreadID(r.ThreadKey),
			"id": r.MessageId, "emoji": r.Reaction, "actor": fmtID(r.ActorId),
		})
	}
	for _, r := range tbl.LSDeleteReaction {
		emit(map[string]any{
			"type": "reaction", "thread": emitThreadID(r.ThreadKey),
			"id": r.MessageId, "emoji": "", "actor": fmtID(r.ActorId),
		})
	}
	// Typing indicator for regular (non-E2EE) threads. (E2EE typing comes via whatsmeow.)
	for _, ti := range tbl.LSUpdateTypingIndicator {
		emit(map[string]any{
			"type": "typing", "thread": emitThreadID(ti.ThreadKey),
			"id": fmtID(ti.SenderId), "composing": ti.IsTyping,
		})
	}
	for _, th := range tbl.LSDeleteThenInsertThread {
		ev := map[string]any{
			"type": "thread", "id": emitThreadID(th.ThreadKey), "name": th.ThreadName,
			"snippet": th.Snippet, "picture": th.ThreadPictureUrl,
			"lastActivity": th.LastActivityTimestampMs,
			"unread":       th.LastActivityTimestampMs > th.LastReadWatermarkTimestampMs,
			"readUpTo":     th.LastReadWatermarkTimestampMs,
			"folder":       normalizeFolder(th.FolderName),
			// MuteExpireTimeMs: 0 = not muted; -1 (or far future) = muted.
			"muted": th.MuteExpireTimeMs != 0 && (th.MuteExpireTimeMs < 0 || th.MuteExpireTimeMs > now),
		}
		if isE2EEKey(th.ThreadKey) {
			ev["contact"] = fmtID(th.ThreadKey) // keep contact lookup pointed at the raw fbid
		}
		emit(ev)
	}
	// Attachments arrive as separate rows; their message row has empty text and would
	// otherwise be dropped. Map each to a labelled placeholder so nothing vanishes.
	attachLabel := map[string]string{}
	for _, a := range tbl.LSInsertAttachment {
		if a.MessageId != "" {
			attachLabel[a.MessageId] = attachTypeLabel(a.AttachmentType)
		}
	}
	for _, a := range tbl.LSInsertStickerAttachment {
		if a.MessageId != "" {
			attachLabel[a.MessageId] = "💟 Sticker"
		}
	}
	// Pictures/stickers in regular chats render inline straight from their CDN URL.
	for _, a := range tbl.LSInsertAttachment {
		if a.MessageId == "" {
			continue
		}
		url := a.PreviewUrl
		if url == "" {
			url = a.PlayableUrl
		}
		kind := ""
		switch a.AttachmentType {
		case table.AttachmentTypeImage, table.AttachmentTypeAnimatedImage:
			kind = "image"
		case table.AttachmentTypeSticker:
			kind = "sticker"
		case table.AttachmentTypeVideo:
			kind, url = "video", a.PlayableUrl
		case table.AttachmentTypeAudio:
			kind, url = "audio", a.PlayableUrl
		case table.AttachmentTypeFile:
			kind, url = "file", a.PlayableUrl
		}
		if kind != "" && url != "" {
			emit(map[string]any{"type": "media", "id": a.MessageId, "thread": emitThreadID(a.ThreadKey), "kind": kind, "url": url})
		}
	}
	for _, a := range tbl.LSInsertStickerAttachment {
		if a.MessageId != "" && a.PlayableUrl != "" {
			emit(map[string]any{"type": "media", "id": a.MessageId, "thread": emitThreadID(a.ThreadKey), "kind": "sticker", "url": a.PlayableUrl})
		}
	}
	emitMsg := func(id string, thread, sender, ts int64, text string, system bool, replyID, replyText string, replyTo int64) {
		if text == "" {
			text = attachLabel[id] // attachment-only message → typed placeholder
		}
		if text == "" {
			return
		}
		ev := map[string]any{
			"type": "message", "id": id, "thread": emitThreadID(thread), "sender": fmtID(sender),
			"text": text, "ts": ts, "live": live, "system": system,
		}
		if replyID != "" { // this message is a reply — carry the quoted source
			ev["replyToId"] = replyID
			if replyText != "" {
				ev["replyToText"] = replyText
			}
			if replyTo != 0 {
				ev["replyToSender"] = fmtID(replyTo)
			}
		}
		emit(ev)
	}
	for _, m := range tbl.LSInsertMessage {
		emitMsg(m.MessageId, m.ThreadKey, m.SenderId, m.TimestampMs, m.Text, m.IsAdminMessage,
			m.ReplySourceId, m.ReplyMessageText, m.ReplyToUserId)
	}
	for _, m := range tbl.LSUpsertMessage {
		emitMsg(m.MessageId, m.ThreadKey, m.SenderId, m.TimestampMs, m.Text, m.IsAdminMessage,
			m.ReplySourceId, m.ReplyMessageText, m.ReplyToUserId)
	}
}

// sendMediaMessage reads a picked file and sends it as a picture. Encrypted threads
// go through the WhatsApp-protocol upload+send; regular threads aren't wired yet.
func sendMediaMessage(threadStr, path, caption string) {
	data, err := os.ReadFile(path)
	if err != nil {
		emit(map[string]any{"type": "error", "msg": "read file: " + err.Error()})
		return
	}
	mime := http.DetectContentType(data)
	kind := "file"
	switch {
	case strings.HasPrefix(mime, "image/"):
		kind = "image"
	case strings.HasPrefix(mime, "video/"):
		kind = "video"
	case strings.HasPrefix(mime, "audio/"):
		kind = "audio"
	}
	w, h := 0, 0
	if kind == "image" {
		if cfg, _, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
			w, h = cfg.Width, cfg.Height
		}
	}
	fileName := filepath.Base(path)
	if strings.HasPrefix(threadStr, "e:") {
		if err := sendE2EEMedia(strings.TrimPrefix(threadStr, "e:"), kind, data, mime, caption, fileName, w, h); err != nil {
			log.Warn().Err(err).Str("kind", kind).Msg("E2EE media send failed")
			emit(map[string]any{"type": "error", "msg": "send media: " + err.Error()})
		}
		return
	}
	if err := sendMediaRegular(threadStr, data, mime, caption, fileName); err != nil {
		log.Warn().Err(err).Str("kind", kind).Msg("media send failed")
		emit(map[string]any{"type": "error", "msg": "send media: " + err.Error()})
	}
}

// sendMediaRegular sends a photo/video/file to a regular (non-encrypted) thread: upload the
// bytes via the Mercury endpoint (same path as group photos) to get a media fbid, then send a
// SendMessageTask that references it. The sent message echoes back through the normal sync.
func sendMediaRegular(threadStr string, data []byte, mime, caption, fileName string) error {
	tid, err := strconv.ParseInt(threadStr, 10, 64)
	if err != nil {
		return err
	}
	if client == nil {
		return fmt.Errorf("not connected")
	}
	if fileName == "" {
		fileName = "upload"
	}
	resp, err := client.SendMercuryUploadRequest(context.Background(), tid, &messagix.MercuryUploadMedia{
		Filename:  fileName,
		MimeType:  mime,
		MediaData: data,
	})
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	fbid := resp.Payload.RealMetadata.GetFbId()
	if fbid == 0 {
		return fmt.Errorf("no media id from upload")
	}
	task := &socket.SendMessageTask{
		ThreadId:         tid,
		Otid:             methods.GenerateEpochID(),
		Source:           table.MESSENGER_INBOX_IN_THREAD,
		InitiatingSource: table.FACEBOOK_INBOX,
		SendType:         table.MEDIA,
		SyncGroup:        1,
		AttachmentFBIds:  []int64{fbid},
		Text:             caption,
	}
	_, err = client.ExecuteTasks(context.Background(), task)
	return err
}

// sendGif sends a GIF to a regular (non-encrypted) thread as an external-media link.
// (Encrypted threads download + upload the GIF as media on the app side instead.)
func sendGif(threadStr, gifURL string) {
	tid, err := strconv.ParseInt(threadStr, 10, 64)
	if err != nil || client == nil {
		return
	}
	task := &socket.SendMessageTask{
		ThreadId:         tid,
		Otid:             methods.GenerateEpochID(),
		Source:           table.MESSENGER_INBOX_IN_THREAD,
		InitiatingSource: table.FACEBOOK_INBOX,
		SendType:         table.EXTERNAL_MEDIA,
		SyncGroup:        1,
		Url:              gifURL,
	}
	if _, err := client.ExecuteTasks(context.Background(), task); err != nil {
		emit(map[string]any{"type": "error", "msg": "gif: " + err.Error()})
	}
}

// unsendMessage deletes one of our messages for everyone.
func unsendMessage(threadStr, msgID string) {
	if msgID == "" {
		return
	}
	if strings.HasPrefix(threadStr, "e:") {
		if err := sendE2EEUnsend(strings.TrimPrefix(threadStr, "e:"), msgID); err != nil {
			emit(map[string]any{"type": "error", "msg": "unsend: " + err.Error()})
		}
		return
	}
	if client == nil {
		return
	}
	if _, err := client.ExecuteTasks(context.Background(), &socket.DeleteMessageTask{MessageId: msgID}); err != nil {
		emit(map[string]any{"type": "error", "msg": "unsend: " + err.Error()})
	}
}

// editMessage changes the text of one of our already-sent messages.
func editMessage(threadStr, msgID, text string) {
	if msgID == "" {
		return
	}
	if strings.HasPrefix(threadStr, "e:") {
		if err := sendE2EEEdit(strings.TrimPrefix(threadStr, "e:"), msgID, text); err != nil {
			emit(map[string]any{"type": "error", "msg": "edit: " + err.Error()})
		}
		return
	}
	if client == nil {
		return
	}
	if _, err := client.ExecuteTasks(context.Background(), &socket.EditMessageTask{MessageID: msgID, Text: text}); err != nil {
		emit(map[string]any{"type": "error", "msg": "edit: " + err.Error()})
	}
}

// sendReaction adds/removes a reaction (emoji "" = remove) on a message.
func sendReaction(threadStr, msgID, emoji string, fromMe bool) {
	if strings.HasPrefix(threadStr, "e:") {
		if err := sendE2EEReaction(strings.TrimPrefix(threadStr, "e:"), msgID, emoji, fromMe); err != nil {
			emit(map[string]any{"type": "error", "msg": "react: " + err.Error()})
		}
		return
	}
	tid, err := strconv.ParseInt(threadStr, 10, 64)
	if err != nil {
		return
	}
	task := &socket.SendReactionTask{
		ThreadKey:       tid,
		MessageID:       msgID,
		ActorID:        	toInt64(selfFBID),
		Reaction:        emoji,
		SyncGroup:       1,
		SendAttribution: table.MESSENGER_INBOX_IN_THREAD,
	}
	if _, err := client.ExecuteTasks(context.Background(), task); err != nil {
		emit(map[string]any{"type": "error", "msg": "react: " + err.Error()})
	}
}

// setMute mutes (forever) or unmutes a conversation. Works for encrypted 1:1
// threads too — their fbid doubles as the Lightspeed thread key.
func setMute(threadStr string, muted bool) {
	tid := toInt64(strings.TrimPrefix(threadStr, "e:"))
	if tid == 0 || client == nil {
		return
	}
	var expire int64 // 0 = unmute
	if muted {
		expire = 9223372036854775807 // max int64 → mute forever
	}
	task := &socket.MuteThreadTask{ThreadKey: tid, MailboxType: 0, MuteExpireTimeMS: expire, SyncGroup: 1}
	if _, err := client.ExecuteTasks(context.Background(), task); err != nil {
		log.Warn().Err(err).Msg("mute failed")
		emit(map[string]any{"type": "error", "msg": "mute: " + err.Error()})
	}
}

// deleteThread removes a whole conversation from the inbox (server-side).
func deleteThread(threadStr string) {
	tid := toInt64(strings.TrimPrefix(threadStr, "e:"))
	if tid == 0 || client == nil {
		return
	}
	task := &socket.DeleteThreadTask{ThreadKey: tid, RemoveType: 0, SyncGroup: 1}
	if _, err := client.ExecuteTasks(context.Background(), task); err != nil {
		log.Warn().Err(err).Msg("delete thread failed")
		emit(map[string]any{"type": "error", "msg": "delete: " + err.Error()})
	}
}

// groupKey is the Lightspeed thread key for a group (strip the "e:" UI namespace).
func groupKey(threadStr string) int64 { return toInt64(strings.TrimPrefix(threadStr, "e:")) }

func runTask(label string, task socket.Task) {
	if client == nil {
		return
	}
	if _, err := client.ExecuteTasks(context.Background(), task); err != nil {
		log.Warn().Err(err).Str("task", label).Msg("group task failed")
		emit(map[string]any{"type": "error", "msg": label + ": " + err.Error()})
	}
}

func renameThread(threadStr, name string) {
	if tid := groupKey(threadStr); tid != 0 {
		runTask("rename", &socket.RenameThreadTask{ThreadKey: tid, ThreadName: name, SyncGroup: 1})
	}
}

func addMembers(threadStr string, idsAny any) {
	tid := groupKey(threadStr)
	if tid == 0 {
		return
	}
	var ids []int64
	if arr, ok := idsAny.([]any); ok {
		for _, v := range arr {
			if id := toInt64(v); id != 0 {
				ids = append(ids, id)
			}
		}
	}
	if len(ids) > 0 {
		runTask("addMembers", &socket.AddParticipantsTask{ThreadKey: tid, ContactIDs: ids, SyncGroup: 1})
	}
}

func removeMember(threadStr, idStr string) {
	tid, cid := groupKey(threadStr), toInt64(idStr)
	if tid != 0 && cid != 0 {
		runTask("removeMember", &socket.RemoveParticipantTask{ThreadID: tid, ContactID: cid})
	}
}

func setThreadAdmin(threadStr, idStr string, admin bool) {
	tid, cid := groupKey(threadStr), toInt64(idStr)
	if tid == 0 || cid == 0 {
		return
	}
	isAdmin := 0
	if admin {
		isAdmin = 1
	}
	runTask("setAdmin", &socket.UpdateAdminTask{ThreadKey: tid, ContactID: cid, IsAdmin: isAdmin})
}

// leaveThread removes ourselves from the group.
func leaveThread(threadStr string) {
	tid, cid := groupKey(threadStr), toInt64(selfFBID)
	if tid != 0 && cid != 0 {
		runTask("leave", &socket.RemoveParticipantTask{ThreadID: tid, ContactID: cid})
	}
}

// setGroupPhoto uploads an image (Mercury) to get an image id, then sets it as the
// group's photo.
func setGroupPhoto(threadStr, path string) {
	tid := groupKey(threadStr)
	if tid == 0 || client == nil {
		return
	}
	data, err := os.ReadFile(path)
	if err != nil {
		emit(map[string]any{"type": "error", "msg": "photo: " + err.Error()})
		return
	}
	resp, err := client.SendMercuryUploadRequest(context.Background(), tid, &messagix.MercuryUploadMedia{
		Filename:  "avatar.jpg",
		MimeType:  http.DetectContentType(data),
		MediaData: data,
	})
	if err != nil {
		emit(map[string]any{"type": "error", "msg": "photo upload: " + err.Error()})
		return
	}
	imageID := resp.Payload.RealMetadata.GetFbId()
	if imageID == 0 {
		emit(map[string]any{"type": "error", "msg": "photo: no image id from upload"})
		return
	}
	runTask("setPhoto", &socket.SetThreadImageTask{ThreadKey: tid, ImageID: imageID, SyncGroup: 1})
}

// createGroup starts a new group conversation with the given participant ids.
func createGroup(name string, idsAny any) {
	if client == nil {
		return
	}
	var ids []int64
	if arr, ok := idsAny.([]any); ok {
		for _, v := range arr {
			if id := toInt64(v); id != 0 {
				ids = append(ids, id)
			}
		}
	}
	if len(ids) == 0 {
		return
	}
	otid := methods.GenerateEpochID()
	task := &socket.CreateGroupTask{
		Participants: ids,
		SendPayload: socket.CreateGroupPayload{
			ThreadID: 0, OTID: strconv.FormatInt(otid, 10), Source: 0, SendType: 8,
		},
	}
	tbl, err := client.ExecuteTasks(context.Background(), task)
	if err != nil {
		emit(map[string]any{"type": "error", "msg": "create group: " + err.Error()})
		return
	}
	if tbl != nil {
		processTable(tbl, true)
	}
	// Name it once it exists (the new thread arrives on the publish stream).
	if name = strings.TrimSpace(name); name != "" && tbl != nil {
		for _, th := range tbl.LSDeleteThenInsertThread {
			if th.ThreadKey != 0 {
				go renameThread(fmtID(th.ThreadKey), name)
			}
		}
	}
}

// markReadServer sends a read receipt so the other side sees "Seen".
func markReadServer(threadStr, msgID, sender string, tsMs int64) {
	if strings.HasPrefix(threadStr, "e:") {
		markE2EERead(strings.TrimPrefix(threadStr, "e:"), msgID, sender, tsMs)
		return
	}
	tid, err := strconv.ParseInt(threadStr, 10, 64)
	if err != nil {
		return
	}
	if tsMs == 0 {
		tsMs = time.Now().UnixMilli()
	}
	task := &socket.ThreadMarkReadTask{ThreadId: tid, LastReadWatermarkTs: tsMs, SyncGroup: 1}
	if _, err := client.ExecuteTasks(context.Background(), task); err != nil {
		log.Debug().Err(err).Msg("mark read failed")
	}
}

func sendMessage(threadStr, text, replyID, replySender, clientTag string) {
	// Encrypted threads (namespaced "e:<fbid>") go through the WhatsApp-protocol
	// E2EE client; everything else through the regular Lightspeed task.
	if strings.HasPrefix(threadStr, "e:") {
		sendE2EE(strings.TrimPrefix(threadStr, "e:"), text, replyID, replySender, clientTag)
		return
	}
	tid, err := strconv.ParseInt(threadStr, 10, 64)
	if err != nil {
		return
	}
	task := &socket.SendMessageTask{
		ThreadId:         tid,
		Otid:             methods.GenerateEpochID(),
		Source:           table.MESSENGER_INBOX_IN_THREAD,
		InitiatingSource: table.FACEBOOK_INBOX,
		SendType:         table.TEXT,
		SyncGroup:        1,
		Text:             text,
	}
	if replyID != "" {
		task.ReplyMetaData = &socket.ReplyMetaData{ReplyMessageId: replyID, ReplySourceType: 1, ReplyType: 0}
	}
	if _, err := client.ExecuteTasks(context.Background(), task); err != nil {
		log.Warn().Err(err).Msg("send failed")
		emit(map[string]any{"type": "error", "msg": "send failed: " + err.Error()})
	}
}

var (
	requestedContacts   = map[int64]bool{}
	requestedContactsMu sync.Mutex
)

// fetchContact pulls a person's full profile (name + avatar) by FBID. This is how
// we resolve people we only know through encrypted threads — their contact row is
// never part of the normal message sync, so without this their chat shows up as
// "Conversation" with no picture. The result comes back as a contact row (handled
// in processTable) both synchronously here and via the live publish stream.
func fetchContact(id int64) {
	if id == 0 || client == nil {
		return
	}
	requestedContactsMu.Lock()
	already := requestedContacts[id]
	requestedContacts[id] = true
	requestedContactsMu.Unlock()
	if already {
		return
	}
	// The socket may not be connected the instant we're asked (the app can trigger
	// this right as we come up), so retry a few times before giving up.
	var lastErr error
	for attempt := 0; attempt < 6; attempt++ {
		tbl, err := client.ExecuteTasks(context.Background(), &socket.GetContactsFullTask{ContactID: id})
		if err == nil {
			if tbl != nil {
				processTable(tbl, true)
			}
			return
		}
		lastErr = err
		time.Sleep(2 * time.Second)
	}
	log.Warn().Err(lastErr).Int64("id", id).Msg("fetchContact gave up")
	requestedContactsMu.Lock()
	delete(requestedContacts, id) // allow a later attempt
	requestedContactsMu.Unlock()
}

// refreshThread pulls the most recent messages for a thread from the server (anchored
// just ahead of "now") and merges them — so opening a chat catches anything sent while
// the app was closed. Works for regular threads; encrypted-chat messages don't live in
// Lightspeed, so this is a no-op for them (they sync over the encrypted channel instead).
func refreshThread(threadStr string) {
	tid := toInt64(strings.TrimPrefix(threadStr, "e:"))
	if tid == 0 || client == nil {
		return
	}
	if strings.HasPrefix(threadStr, "e:") {
		markE2EEKey(tid)
	}
	task := &socket.FetchMessagesTask{
		ThreadKey:            tid,
		Direction:            0,
		ReferenceTimestampMs: time.Now().UnixMilli() + 60_000, // just ahead of now → newest messages
		ReferenceMessageId:   "",
		SyncGroup:            1,
		Cursor:               client.GetCursor(1),
	}
	if tbl, err := client.ExecuteTasks(context.Background(), task); err != nil {
		log.Warn().Err(err).Int64("thread", tid).Msg("refreshThread failed")
	} else if tbl != nil {
		processTable(tbl, true)
	}
}

// loadEarlier backfills older messages before the oldest one the app currently has.
// Encrypted threads request on-demand history from the phone; regular threads use
// the Lightspeed FetchMessages task.
func loadEarlier(threadStr, oldestID string, oldestTs int64, fromMe bool) {
	// Both regular AND encrypted 1:1 threads backfill through the same Lightspeed
	// fetch — Meta serves history for E2EE-over-WA one-to-one chats the same way
	// (only E2EE *groups* are excluded). The E2EE thread id is "e:<fbid>" where the
	// fbid doubles as the Lightspeed thread key. The Cursor is required or the server
	// ignores the request. Results arrive asynchronously via the publish stream.
	tid := toInt64(strings.TrimPrefix(threadStr, "e:"))
	if tid == 0 || client == nil {
		return
	}
	if strings.HasPrefix(threadStr, "e:") {
		markE2EEKey(tid) // so the backfilled messages merge into the encrypted thread
	}
	task := &socket.FetchMessagesTask{
		ThreadKey:            tid,
		Direction:            0,
		ReferenceTimestampMs: oldestTs,
		ReferenceMessageId:   oldestID,
		SyncGroup:            1,
		Cursor:               client.GetCursor(1),
	}
	tbl, err := client.ExecuteTasks(context.Background(), task)
	if err != nil {
		log.Warn().Err(err).Int64("thread", tid).Msg("fetch messages failed")
		emit(map[string]any{"type": "error", "msg": "history: " + err.Error()})
		return
	}
	if tbl != nil {
		processTable(tbl, true)
	}
	log.Info().Int64("thread", tid).Str("before", oldestID).Msg("requested earlier history")
}

// IDs are int64 up to ~2.5e16 — beyond float64's exact range — so they cross the
// JSON boundary as strings in both directions.
func fmtID(x int64) string { return strconv.FormatInt(x, 10) }

func toInt64(v any) int64 {
	switch n := v.(type) {
	case string:
		x, _ := strconv.ParseInt(n, 10, 64)
		return x
	case float64:
		return int64(n)
	case int64:
		return n
	}
	return 0
}
