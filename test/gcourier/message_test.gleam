import gcourier
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn basic_build_test() {
  let msg = gcourier.new_message()

  msg.headers |> dict.size |> should.equal(0)
  msg.to |> list.is_empty |> should.be_true
  msg.cc |> list.is_empty |> should.be_true
  msg.bcc |> list.is_empty |> should.be_true
  msg.content |> should.equal("")
}

pub fn from_address_test() {
  let msg =
    gcourier.new_message()
    |> gcourier.set_from("test@example.com", Some("Test User"))

  let assert Ok(from) = dict.get(msg.headers, "From")
  from |> should.equal("Test User <test@example.com>")

  let msg =
    gcourier.new_message() |> gcourier.set_from("test@example.com", None)

  let assert Ok(from) = dict.get(msg.headers, "From")
  from |> should.equal("test@example.com")
}

pub fn sender_header_test() {
  let msg =
    gcourier.new_message()
    |> gcourier.set_sender("sender@example.com", Some("Sender Name"))

  dict.get(msg.headers, "Sender")
  |> should.equal(Ok("Sender Name <sender@example.com>"))
}

pub fn recipients_test() {
  let msg =
    gcourier.new_message()
    |> gcourier.add_recipient("to@example.com", gcourier.To)
    |> gcourier.add_recipient("cc@example.com", gcourier.CC)
    |> gcourier.add_recipient("bcc@example.com", gcourier.BCC)

  msg.to |> should.equal(["to@example.com"])
  msg.cc |> should.equal(["cc@example.com"])
  msg.bcc |> should.equal(["bcc@example.com"])

  let msg =
    msg
    |> gcourier.add_recipient("to2@example.com", gcourier.To)
    |> gcourier.add_recipient("cc2@example.com", gcourier.CC)
    |> gcourier.add_recipient("bcc2@example.com", gcourier.BCC)

  msg.to |> should.equal(["to2@example.com", "to@example.com"])
  msg.cc |> should.equal(["cc2@example.com", "cc@example.com"])
  msg.bcc |> should.equal(["bcc2@example.com", "bcc@example.com"])
}

pub fn subject_test() {
  let msg =
    gcourier.new_message()
    |> gcourier.set_subject("Test Subject")

  dict.get(msg.headers, "Subject")
  |> should.equal(Ok("Test Subject"))
}

pub fn content_type_test() {
  let msg = gcourier.new_message()
  dict.get(msg.headers, "Content-Type") |> should.be_error()

  let text_msg =
    gcourier.new_message()
    |> gcourier.set_text("Test message")

  dict.get(text_msg.headers, "Content-Type")
  |> should.equal(Ok("text/plain"))

  let html_msg =
    gcourier.new_message()
    |> gcourier.set_html("<p>Test HTML</p>")

  dict.get(html_msg.headers, "Content-Type")
  |> should.equal(Ok("text/html"))

  html_msg.content
  |> should.equal("<p>Test HTML</p>")
}

pub fn render_headers_test() {
  let msg =
    gcourier.new_message()
    |> gcourier.set_from("from@example.com", None)
    |> gcourier.add_recipient("to@example.com", gcourier.To)
    |> gcourier.set_subject("Test Subject")
    |> gcourier.set_text("Hello world")

  let assert Ok(rendered) = gcourier.render(msg)

  let should_contain = fn(a: String, b: String) {
    should.be_true(string.contains(a, b))
  }

  rendered |> should_contain("From: from@example.com")
  rendered |> should_contain("To: to@example.com")
  rendered |> should_contain("Subject: Test Subject")
  rendered |> should_contain("Content-Type: text/plain")

  rendered |> should_contain("Hello world")
}

pub fn missing_from_test() {
  let msg =
    gcourier.new_message()
    |> gcourier.add_recipient("to@example.com", gcourier.To)
    |> gcourier.set_subject("Test Subject")
    |> gcourier.set_text("Hello world")

  let rendered = gcourier.render(msg)

  assert rendered == Error(gcourier.MissingFrom)
}

pub fn missing_to_test() {
  let msg =
    gcourier.new_message()
    |> gcourier.set_from("from@example.com", None)
    |> gcourier.set_subject("Test Subject")
    |> gcourier.set_text("Hello world")

  let rendered = gcourier.render(msg)

  assert rendered == Error(gcourier.MissingRecipientTo)
}

pub fn week_day_test() {
  // Basic tests for each day of the week
  gcourier.day_of_week(10, 5, 2025) |> should.equal("Sat")
  gcourier.day_of_week(11, 5, 2025) |> should.equal("Sun")
  gcourier.day_of_week(12, 5, 2025) |> should.equal("Mon")
  gcourier.day_of_week(13, 5, 2025) |> should.equal("Tue")
  gcourier.day_of_week(14, 5, 2025) |> should.equal("Wed")
  gcourier.day_of_week(15, 5, 2025) |> should.equal("Thu")
  gcourier.day_of_week(16, 5, 2025) |> should.equal("Fri")

  // Month boundaries
  gcourier.day_of_week(1, 1, 2025) |> should.equal("Wed")
  gcourier.day_of_week(31, 1, 2025) |> should.equal("Fri")
  gcourier.day_of_week(1, 2, 2025) |> should.equal("Sat")
  gcourier.day_of_week(28, 2, 2025) |> should.equal("Fri")

  // Leap year tests
  gcourier.day_of_week(29, 2, 2024) |> should.equal("Thu")
  gcourier.day_of_week(1, 3, 2024) |> should.equal("Fri")
  gcourier.day_of_week(1, 3, 2025) |> should.equal("Sat")

  // Various months and years
  gcourier.day_of_week(4, 7, 1776) |> should.equal("Thu")
  gcourier.day_of_week(25, 12, 2024) |> should.equal("Wed")
  gcourier.day_of_week(31, 10, 2025) |> should.equal("Fri")
  gcourier.day_of_week(11, 11, 2025) |> should.equal("Tue")

  // Historical dates
  gcourier.day_of_week(1, 1, 2000) |> should.equal("Sat")
  gcourier.day_of_week(30, 6, 1969) |> should.equal("Mon")
  gcourier.day_of_week(20, 7, 1969) |> should.equal("Sun")
  gcourier.day_of_week(21, 12, 2012) |> should.equal("Fri")

  // Edge cases
  gcourier.day_of_week(29, 2, 2000) |> should.equal("Tue")
  gcourier.day_of_week(31, 12, 1999) |> should.equal("Fri")
  gcourier.day_of_week(1, 1, 1900) |> should.equal("Mon")
}
