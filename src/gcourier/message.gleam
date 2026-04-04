//// This module provides tools for constructing RFC-compliant email messages.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import youid/uuid

pub type MessageCreationError {
  MissingContentTypeHeader
  MissingAttachments
  MissingFrom
  MissingRecipientTo
}

pub type Attachment {
  Attachment(name: String, content_type: String, content: String)
}

pub type Message {
  Message(
    headers: Dict(String, String),
    to: List(String),
    cc: List(String),
    bcc: List(String),
    content: String,
    attachments: Option(List(Attachment)),
  )
}

pub type RecipientType {
  To
  CC
  BCC
}

pub fn build() -> Message {
  Message(dict.from_list([]), [], [], [], "", None)
}

pub fn render(message: Message) -> Result(String, MessageCreationError) {
  case message.attachments {
    Some(_) -> render_multipart(message)
    None -> render_single(message)
  }
}

fn render_single(message: Message) -> Result(String, MessageCreationError) {
  use headers <- result.try(get_headers(message))

  let headers =
    headers
    |> list.map(fn(header) { header.0 <> ": " <> header.1 })
    |> string.join("\r\n")

  Ok(headers <> "\r\n\r\n" <> message.content <> "\r\n.")
}

fn render_multipart(message: Message) -> Result(String, MessageCreationError) {
  let boundary = uuid.v4_string()
  use body_ctype <- result.try(
    dict.get(message.headers, "Content-Type")
    |> result.replace_error(MissingContentTypeHeader),
  )
  let message =
    message
    |> set_header(
      "Content-Type",
      "multipart/mixed; boundary=\"" <> boundary <> "\"",
    )

  use attachments <- result.try(
    message.attachments |> option.to_result(MissingAttachments),
  )
  let content =
    "--"
    <> boundary
    <> "\r\nContent-Type: "
    <> body_ctype
    <> "\r\n\r\n"
    <> message.content
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

  use headers <- result.try(get_headers(message))

  let headers =
    headers
    |> list.map(fn(header) { header.0 <> ": " <> header.1 })
    |> string.join("\r\n")

  Ok(headers <> "\r\n" <> content <> "\r\n.")
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

fn get_headers(
  message: Message,
) -> Result(List(#(String, String)), MessageCreationError) {
  let get = fn(name) { dict.get(message.headers, name) }
  let key = fn(value, name) { #(name, value) }

  let date =
    get("Date")
    |> result.unwrap(current_date())
    |> key("Date")

  use from <- result.try(case get("From") {
    Error(_) -> MissingFrom |> Error
    Ok(value) -> #("From", value) |> Ok
  })

  use recipient_to <- result.try(case message.to {
    [] -> Error(MissingRecipientTo)
    _ -> Ok(#("To", string.join(message.to, ", ")))
  })

  let sender = get("Sender") |> result.map(key(_, "Sender"))

  let recipient_cc = case message.cc {
    [] -> Error(Nil)
    _ -> Ok(#("To", string.join(message.to, ", ")))
  }

  let subject = get("Subject") |> result.map(key(_, "Subject"))

  let content_type =
    get("Content-Type")
    |> result.unwrap("text/plain")
    |> key("Content-Type")

  [
    Ok(date),
    Ok(from),
    Ok(recipient_to),
    sender,
    recipient_cc,
    subject,
    Ok(content_type),
  ]
  // filter out missing optional headers
  |> list.filter_map(fn(item) { item })
  |> Ok
}

// Header setting functions

/// Set the FROM header in the email.
pub fn set_from(
  message: Message,
  sender_address address: String,
  sender_name name: Option(String),
) -> Message {
  message |> set_header("From", format_address(address, name))
}

/// Add the provided address to the list of recipients.
/// 
/// recipient_type should be one of To, Cc, or Bcc.
pub fn add_recipient(
  message: Message,
  email: String,
  recipient_type: RecipientType,
) -> Message {
  case recipient_type {
    To -> Message(..message, to: [email, ..message.to])
    CC -> Message(..message, cc: [email, ..message.cc])
    BCC -> Message(..message, bcc: [email, ..message.bcc])
  }
}

/// Set the message's subject line. Optional.
pub fn set_subject(message: Message, subject: String) -> Message {
  message |> set_header("Subject", subject)
}

/// Set the _optional_ sender header. Prefer FROM in most cases.
/// 
/// This field is useful when the email is sent on behalf of 
/// a third party or there are multiple emails in the FROM field.
pub fn set_sender(
  message: Message,
  sender_address address: String,
  sender_name name: Option(String),
) -> Message {
  message |> set_header("Sender", format_address(address, name))
}

/// Set the Date header for the email. Optional.
///
/// If this is not explicitly set, the current system time will be used automatically
/// when the message is sent. This header indicates when the email was created.
pub fn set_date(message: Message, date: String) -> Message {
  message |> set_header("Date", date)
}

// Content functions

pub fn set_html(message: Message, html: String) -> Message {
  message
  |> set_header("Content-Type", "text/html")
  |> set_content(html)
}

pub fn set_text(message: Message, text: String) -> Message {
  message
  |> set_header("Content-Type", "text/plain")
  |> set_content(text)
}

pub fn add_attachment(
  message: Message,
  content: BitArray,
  name: String,
  content_type: String,
) -> Message {
  let content = bit_array.base64_encode(content, False)

  let attachment = Attachment(name:, content_type:, content:)
  let attachments = case message.attachments {
    None -> [attachment]
    Some(a) -> [attachment, ..a]
  }
  Message(..message, attachments: Some(attachments))
}

fn set_content(message: Message, text: String) -> Message {
  Message(..message, content: text)
}

// Utility functions

fn set_header(message: Message, name: String, value: String) -> Message {
  Message(..message, headers: dict.insert(message.headers, name, value))
}

fn format_address(address: String, name: Option(String)) -> String {
  case name {
    Some(name) -> {
      name <> " <" <> address <> ">"
    }
    None -> address
  }
}

@internal
pub fn date_from_cal(
  date cal: calendar.Date,
  time time: calendar.TimeOfDay,
) -> String {
  let month = {
    calendar.month_to_string(cal.month) |> string.slice(0, 3)
  }

  let offset = float.round(duration.to_seconds(calendar.local_offset()))
  let offset_sign = case offset > 0 {
    True -> "+"
    False -> ""
  }

  let offset_hours =
    { offset / 3600 } |> int.to_string |> string.pad_start(2, "0")
  let offset_minutes =
    { { offset % 3600 } / 60 } |> int.to_string |> string.pad_start(2, "0")

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
  <> " "
  <> offset_sign
  <> offset_hours
  <> ":"
  <> offset_minutes
}

@internal
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
    6 -> "Fri"
    _ -> panic
  }
}

fn current_date() -> String {
  let now =
    timestamp.system_time() |> timestamp.to_calendar(duration.seconds(0))

  date_from_cal(now.0, now.1)
}
