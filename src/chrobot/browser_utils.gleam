//// Utility functions for common browser automation tasks.
//// Provides URL waiting and element visibility checking capabilities.

import chrobot
import chrobot/chrome
import gleam/dynamic/decode
import gleam/result
import gleam/string

/// Get the current page URL.
pub fn get_url(page: chrobot.Page) -> Result(String, chrome.RequestError) {
  chrobot.eval_to_value(on: page, js: "window.location.href")
  |> chrobot.as_value(decode.string)
}

/// Wait until the page URL matches the given predicate.
/// The timeout is specified in milliseconds.
///
/// ## Example
/// ```gleam
/// // Wait up to 5 minutes for URL to change away from login page
/// wait_for_url(page, matching: fn(url) { !string.contains(url, "login") }, time_out: 300_000)
/// ```
pub fn wait_for_url(
  page page: chrobot.Page,
  matching predicate: fn(String) -> Bool,
  time_out timeout: Int,
) -> Result(String, chrome.RequestError) {
  chrobot.poll(
    fn() {
      use url <- result.try(get_url(page))
      case predicate(url) {
        True -> Ok(url)
        False -> Error(chrome.NotFoundError)
      }
    },
    timeout,
  )
}

/// Check if an element matching the CSS selector is visible on the page.
/// Returns True if the element exists in the DOM and is visually visible.
pub fn is_visible(
  page page: chrobot.Page,
  selector selector: String,
) -> Result(Bool, chrome.RequestError) {
  let escaped_selector = string.replace(selector, "\\", "\\\\")
  let escaped_selector = string.replace(escaped_selector, "\"", "\\\"")
  let js = "(function() {
  var el = document.querySelector(\"" <> escaped_selector <> "\");
  if (!el) return false;
  var style = window.getComputedStyle(el);
  if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
  return el.offsetParent !== null || el.offsetWidth > 0 || el.offsetHeight > 0;
})()"
  chrobot.eval_to_value(on: page, js: js)
  |> chrobot.as_value(decode.bool)
}

/// Wait until an element matching the CSS selector becomes visible.
/// The timeout is specified in milliseconds.
///
/// ## Example
/// ```gleam
/// await_visible(page, selector: "#my-element", time_out: 10_000)
/// ```
pub fn await_visible(
  page page: chrobot.Page,
  selector selector: String,
  time_out timeout: Int,
) -> Result(Bool, chrome.RequestError) {
  chrobot.poll(
    fn() {
      use visible <- result.try(is_visible(page: page, selector: selector))
      case visible {
        True -> Ok(True)
        False -> Error(chrome.NotFoundError)
      }
    },
    timeout,
  )
}
