import gcourier/mug/mug
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import youid/uuid

// messages ---------------------------------------------------------------------

pub type MessageCreationError {
  MissingContentTypeHeader
  MissingAttachments
  MissingFrom
  MissingRecipientTo
}

pub type Attachment {
  Attachment(name: String, content_type: String, content: String)
}

pub opaque type Message {
  /// primary_recipient ***HAS*** to contain at least one 
  /// done in `new_message`
  Simple(data: MessageData)
  MultiPart(data: MessageData, attachments: List(Attachment))
}

type MessageData {
  MessageData(
    // Required
    from: Address,
    content: Content,
    // Optional 
    subject: Option(String),
    content_type_override: Option(String),
    to: List(Recipient),
    cc: List(Recipient),
    bcc: List(Recipient),
    timestamp: Option(timestamp.Timestamp),
    sender: Option(Address),
  )
}

pub type Recipient {
  To(address: String)
  Cc(address: String)
  Bcc(address: String)
}

pub type Address {
  Address(name: Option(String), address: String)
}

pub type Content {
  Text(text: String)
  Html(text: String)
}

fn content_type(content: Content) -> String {
  case content {
    Text(text: _) -> "text/plain"
    Html(text: _) -> "text/html"
  }
}

pub fn new_message(from from: Address) -> Message {
  Simple(data: MessageData(
    from:,
    content: Text(""),
    subject: None,
    to: [],
    cc: [],
    bcc: [],
    timestamp: None,
    content_type_override: None,
    sender: None,
  ))
}

pub fn render(message: Message) -> String {
  case message {
    Simple(data:) -> render_single(data)
    MultiPart(data:, attachments:) -> render_multipart(data, attachments)
  }
}

fn render_single(message: MessageData) -> String {
  let headers = format_headers(message)

  headers <> "\r\n" <> message.content.text <> "\r\n."
}

fn render_multipart(
  message: MessageData,
  attachments: List(Attachment),
) -> String {
  let boundary = uuid.v4_string()

  let message =
    MessageData(
      ..message,
      content_type_override: Some(
        "multipart/mixed; boundary=\"" <> boundary <> "\"",
      ),
    )

  let content =
    "--"
    <> boundary
    <> "\r\nContent-Type: "
    <> content_type(message.content)
    <> "\r\n\r\n"
    <> message.content.text
    <> "\r\n"
    <> {
      list.map(list.reverse(attachments), fn(a) {
        render_attachment(boundary, a)
      })
      |> string.join(with: "\r\n")
    }
    <> "\r\n--"
    <> boundary
    <> "--\r\n"

  let headers = format_headers(message)

  headers <> "\r\n" <> content <> "\r\n."
}

fn render_attachment(boundary: String, attachment: Attachment) -> String {
  "--"
  <> boundary
  <> "\r\nContent-Type: "
  <> attachment.content_type
  <> "\r\nContent-Disposition: "
  <> "attachment; filename=\""
  <> attachment.name
  <> "\"\r\n"
  <> "Content-Transfer-Encoding: base64\r\n\r\n"
  <> attachment.content
}

fn format_headers(message: MessageData) -> String {
  let with_key = fn(key, value) { key <> ": " <> value <> "\r\n" }

  let optional_with_key = fn(key, optional_value) {
    case optional_value {
      Some(value) -> with_key(key, value)
      None -> ""
    }
  }

  let optional_list_with_key = fn(
    key: String,
    list: List(a),
    transform: fn(a) -> String,
  ) -> String {
    case list {
      [] -> ""
      [_, ..] ->
        key <> ": " <> list.map(list, transform) |> string.join(", ") <> "\r\n"
    }
  }

  let format_sender = fn(sender: Address) {
    format_address(sender.address, sender.name)
  }

  let _ =
    with_key(
      "Date",
      message.timestamp
        |> option.unwrap(timestamp.system_time())
        |> date_from_timestamp(),
    )
    <> with_key("From", format_address(message.from.address, message.from.name))
    <> optional_list_with_key("To", message.to, fn(item) { item.address })
    <> optional_with_key("Sender", message.sender |> option.map(format_sender))
    <> optional_list_with_key("Cc", message.cc, fn(item) { item.address })
    <> optional_with_key("Subject", message.subject)
    <> with_key(
      "Content-Type",
      message.content_type_override
        |> option.unwrap(message.content |> content_type()),
    )
}

// Header setting functions

/// Add the provided address to the list of recipients.
/// 
/// recipient_type should be one of To, Cc, or Bcc.
///
/// We implement the first variant of bcc handling layed out in [RFC 5322](https://www.rfc-editor.org/rfc/rfc5322#section-3.6.3)
/// i.e.: The bcc header does not end up in the actual message
/// if you need one of the other implementations, feel free to [open an issue](https://github.com/gideongrinberg/gcourier/issues)
///
pub fn add_recipient(message: Message, recipient: Recipient) -> Message {
  case recipient {
    To(_) -> MessageData(..message.data, to: [recipient, ..message.data.to])
    Cc(_) -> MessageData(..message.data, cc: [recipient, ..message.data.cc])
    Bcc(_) -> MessageData(..message.data, bcc: [recipient, ..message.data.bcc])
  }
  |> update_message_data(message, _)
}

/// Set the message's subject line. Optional.
pub fn set_subject(message: Message, subject: String) -> Message {
  update_message_data(
    message,
    MessageData(..message.data, subject: Some(subject)),
  )
}

/// Set the _optional_ sender header. 
/// 
/// This field is useful when the email is sent on behalf of 
/// a third party or there are multiple emails in the FROM field.
pub fn set_sender(message: Message, sender: Address) -> Message {
  update_message_data(
    message,
    MessageData(..message.data, sender: Some(sender)),
  )
}

/// Set the Date header for the email. Optional.
///
/// If this is not explicitly set, the current system time will be used automatically
/// when the message is sent. This header indicates when the email was created.
///
pub fn set_timestamp(
  message: Message,
  timestamp: timestamp.Timestamp,
) -> Message {
  update_message_data(
    message,
    MessageData(..message.data, timestamp: Some(timestamp)),
  )
}

// Content functions

/// set the content of a message
///
/// there can only be one content set. i.e. a second usage of this function will overwrite the first
///
pub fn set_content(message: Message, content: Content) -> Message {
  update_message_data(message, MessageData(..message.data, content:))
}

/// add an attachment to a message
///
pub fn add_attachment(
  message: Message,
  content: BitArray,
  name: String,
  content_type: String,
) -> Message {
  let content = bit_array.base64_encode(content, False)

  let attachment = Attachment(name:, content_type:, content:)

  case message {
    Simple(data:) -> MultiPart(data:, attachments: [attachment])
    MultiPart(data:, attachments:) ->
      MultiPart(data:, attachments: [attachment, ..attachments])
  }
}

// Utility functions ------------------------------------------------------------

fn update_message_data(message: Message, data: MessageData) -> Message {
  case message {
    Simple(..) -> Simple(data:)
    MultiPart(..) -> MultiPart(..message, data:)
  }
}

fn format_address(address: String, name: Option(String)) -> String {
  case name {
    Some(name) -> {
      name <> " <" <> address <> ">"
    }
    None -> address
  }
}

fn date_from_timestamp(timestamp: timestamp.Timestamp) -> String {
  let #(cal, time) = timestamp |> timestamp.to_calendar(calendar.utc_offset)

  let month = {
    calendar.month_to_string(cal.month) |> string.slice(0, 3)
  }

  day_of_week(cal.day, calendar.month_to_int(cal.month), cal.year)
  <> ", "
  <> int.to_string(cal.day)
  <> " "
  <> month
  <> " "
  <> int.to_string(cal.year)
  <> " "
  <> int.to_string(time.hours)
  <> ":"
  <> int.to_string(time.minutes)
  <> ":"
  <> int.to_string(time.seconds)
  // since we always use UTC
  <> " +0000"
}

pub fn day_of_week(day q: Int, month m: Int, year y: Int) -> String {
  let y = case m < 3 {
    True -> y - 1
    False -> y
  }

  let m = case m < 3 {
    True -> m + 12
    False -> m
  }

  let k = y % 100
  let j = y / 100

  let h = q + { 13 * { m + 1 } / 5 } + k + k / 4 + j / 4 + 5 * j
  case h % 7 {
    0 -> "Sat"
    1 -> "Sun"
    2 -> "Mon"
    3 -> "Tue"
    4 -> "Wed"
    5 -> "Thu"
    _ -> "Fri"
  }
}

// message sending --------------------------------------------------------------

type Mailer {
  SmtpMailer(
    host: String,
    port: Int,
    username: String,
    password: String,
    auth: Bool,
  )
}

pub type Error {
  FailedToConnect(mug.Error)
  FailedToReceive(mug.Error)
  InvalidUtf8Response(BitArray)
  FailedToSend(mug.Error)
  FailedToUpgrade(mug.Error)
}

pub fn send(
  host: String,
  port: Int,
  auth: Option(#(String, String)),
  message: Message,
) -> Result(Nil, Error) {
  let mailer = case auth {
    Some(#(username, password)) ->
      SmtpMailer(host:, port:, username:, password:, auth: True)
    None -> SmtpMailer(host:, port:, username: "", password: "", auth: False)
  }

  send_smtp(mailer, message)
}

fn send_smtp(mailer: Mailer, msg: Message) -> Result(Nil, Error) {
  use socket <- result.try(
    connect_smtp(SmtpMailer(
      host: mailer.host,
      port: mailer.port,
      username: mailer.username,
      password: mailer.password,
      auth: mailer.auth,
    )),
  )

  let from_cmd = "MAIL FROM:<" <> mailer.username <> ">"
  use _ <- result.try(socket_send_checked(socket, from_cmd))
  use _ <- result.try(socket_receive(socket))

  let rcpt =
    list.map(msg.data.to, fn(recipient) {
      let to_cmd = "RCPT TO:<" <> recipient.address <> ">"
      use _ <- result.try(socket_send_checked(socket, to_cmd))
      socket_receive(socket)
    })
    |> result.all()
  use _ <- result.try(rcpt)

  use _ <- result.try(socket_send_checked(socket, "DATA"))
  use _ <- result.try(socket_receive(socket))

  let message = render(msg)
  use _ <- result.try(socket_send_checked(socket, message))
  use _ <- result.try(socket_receive(socket))

  use _ <- result.try(socket_send_checked(socket, "QUIT"))
  use _ <- result.try(socket_receive(socket))
  Ok(Nil)
}

fn socket_send_checked(socket: mug.Socket, value: String) -> Result(Nil, Error) {
  socket_send(socket, value)
}

fn socket_send(socket: mug.Socket, value: String) -> Result(Nil, Error) {
  mug.send(socket, <<{ value <> "\r\n" }:utf8>>)
  |> result.map_error(FailedToSend)
}

fn socket_receive(socket: mug.Socket) -> Result(String, Error) {
  use packet <- result.try(
    mug.receive(socket, 5000) |> result.map_error(FailedToReceive),
  )
  bit_array.to_string(packet)
  |> result.replace_error(InvalidUtf8Response(packet))
}

fn connect_smtp(mailer: Mailer) -> Result(mug.Socket, Error) {
  use socket <- result.try(
    mug.new(mailer.host, mailer.port)
    |> mug.timeout(milliseconds: 500)
    |> mug.connect()
    |> result.map_error(FailedToConnect),
  )

  use resp <- result.try(socket_receive(socket))

  let ehlo = case string.contains(resp, "ESMTP") {
    True -> socket_send(socket, "EHLO " <> mailer.host)
    False -> socket_send(socket, "HELO " <> mailer.host)
  }
  use _ <- result.try(ehlo)

  use helo_resp <- result.try(socket_receive(socket))

  let ehlo = case string.contains(helo_resp, "STARTTLS") {
    False -> #(helo_resp, socket) |> Ok
    True -> {
      use _ <- result.try(socket_send_checked(socket, "STARTTLS"))
      use _ <- result.try(
        mug.receive(socket, 5000) |> result.map_error(FailedToReceive),
      )

      use socket <- result.try(
        mug.upgrade(socket, mug.DangerouslyDisableVerification, 10_000)
        |> result.map_error(FailedToUpgrade),
      )
      use _ <- result.try(socket_send_checked(socket, "EHLO " <> mailer.host))
      use resp <- result.try(socket_receive(socket))
      #(resp, socket) |> Ok
    }
  }
  use #(helo_resp, socket) <- result.try(ehlo)

  use _ <- result.try(case mailer.auth {
    False -> Ok(Nil)
    True -> auth_user(socket, mailer, helo_resp)
  })

  socket
  |> Ok
}

fn auth_user(
  socket: mug.Socket,
  mailer: Mailer,
  helo_resp: String,
) -> Result(Nil, Error) {
  case string.contains(helo_resp, "AUTH") {
    False -> {
      io.println_error(
        "SMTP server does not support authentication. Proceeding as unauthenticated user.",
      )
      |> Ok
    }
    True -> {
      use _ <- result.try(socket_send_checked(socket, "AUTH LOGIN"))
      use _ <- result.try(socket_receive(socket))
      // todo: check resp
      use _ <- result.try(socket_send_checked(
        socket,
        mailer.username
          |> bit_array.from_string()
          |> bit_array.base64_encode(True),
      ))

      use _ <- result.try(socket_receive(socket))
      use _ <- result.try(socket_send_checked(
        socket,
        mailer.password
          |> bit_array.from_string()
          |> bit_array.base64_encode(True),
      ))
      use _ <- result.try(socket_receive(socket))
      Ok(Nil)
    }
  }
}
