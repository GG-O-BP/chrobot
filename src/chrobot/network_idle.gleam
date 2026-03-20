//// Network idle detection for chrobot.
//// Tracks active network requests and waits until no requests are in-flight
//// for a specified quiet period, similar to Playwright's `networkidle`.

import chrobot
import chrobot/chrome
import chrobot/internal/utils
import chrobot/protocol/network
import gleam/dynamic as d
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/option
import gleam/result
import gleam/set.{type Set}

/// Active network idle listener handle
pub opaque type IdleListener {
  IdleListener(
    browser: Subject(chrome.Message),
    request_will_be_sent: Subject(d.Dynamic),
    loading_finished: Subject(d.Dynamic),
    loading_failed: Subject(d.Dynamic),
  )
}

/// Start tracking network activity on the given page.
/// Enables the Network domain and subscribes to request start/finish/fail events.
pub fn start(
  page: chrobot.Page,
) -> Result(IdleListener, chrome.RequestError) {
  use _ <- result.try(network.enable(
    chrobot.page_caller(page),
    max_post_data_size: option.None,
  ))
  let request_will_be_sent =
    chrome.add_listener(page.browser, "Network.requestWillBeSent")
  let loading_finished =
    chrome.add_listener(page.browser, "Network.loadingFinished")
  let loading_failed =
    chrome.add_listener(page.browser, "Network.loadingFailed")
  Ok(IdleListener(
    browser: page.browser,
    request_will_be_sent: request_will_be_sent,
    loading_finished: loading_finished,
    loading_failed: loading_failed,
  ))
}

/// Remove all event listeners.
pub fn stop(listener: IdleListener) -> Nil {
  chrome.remove_listener(listener.browser, listener.request_will_be_sent)
  chrome.remove_listener(listener.browser, listener.loading_finished)
  chrome.remove_listener(listener.browser, listener.loading_failed)
}

/// Defer pattern for use expressions.
pub fn defer_stop(listener: IdleListener, body: fn() -> a) -> a {
  let result = body()
  stop(listener)
  result
}

/// Wait until no network requests are in-flight for `quiet_ms` milliseconds.
/// Returns `Error(ChromeAgentTimeout)` if the total `time_out` is exceeded.
pub fn wait_for_idle(
  listener: IdleListener,
  quiet_ms quiet_ms: Int,
  time_out timeout: Int,
) -> Result(Nil, chrome.RequestError) {
  let deadline = utils.get_time_ms() + timeout
  let last_activity = utils.get_time_ms()
  idle_loop(listener, set.new(), last_activity, quiet_ms, deadline)
}

type EventKind {
  RequestStarted(d.Dynamic)
  RequestFinished(d.Dynamic)
  RequestFailed(d.Dynamic)
}

fn idle_loop(
  listener: IdleListener,
  active: Set(String),
  last_activity: Int,
  quiet_ms: Int,
  deadline: Int,
) -> Result(Nil, chrome.RequestError) {
  let now = utils.get_time_ms()

  // Check timeout
  case now > deadline {
    True -> Error(chrome.ChromeAgentTimeout)
    False -> {
      // Check if idle condition is met
      case set.is_empty(active) && now - last_activity >= quiet_ms {
        True -> Ok(Nil)
        False -> {
          let selector =
            process.new_selector()
            |> process.select_map(listener.request_will_be_sent, RequestStarted)
            |> process.select_map(listener.loading_finished, RequestFinished)
            |> process.select_map(listener.loading_failed, RequestFailed)

          case process.selector_receive(from: selector, within: 10) {
            Ok(event) -> {
              let #(new_active, new_last_activity) =
                handle_event(event, active, now)
              idle_loop(
                listener,
                new_active,
                new_last_activity,
                quiet_ms,
                deadline,
              )
            }
            Error(Nil) -> {
              idle_loop(listener, active, last_activity, quiet_ms, deadline)
            }
          }
        }
      }
    }
  }
}

fn handle_event(
  event: EventKind,
  active: Set(String),
  now: Int,
) -> #(Set(String), Int) {
  case event {
    RequestStarted(dyn) -> {
      case decode_request_id(dyn) {
        Ok(id) -> #(set.insert(active, id), now)
        Error(_) -> #(active, now)
      }
    }
    RequestFinished(dyn) -> remove_request(dyn, active, now)
    RequestFailed(dyn) -> remove_request(dyn, active, now)
  }
}

fn remove_request(
  dyn: d.Dynamic,
  active: Set(String),
  now: Int,
) -> #(Set(String), Int) {
  case decode_request_id(dyn) {
    Ok(id) -> #(set.delete(active, id), now)
    Error(_) -> #(active, now)
  }
}

fn decode_request_id(dyn: d.Dynamic) -> Result(String, List(decode.DecodeError)) {
  let decoder = {
    use request_id <- decode.field("requestId", decode.string)
    decode.success(request_id)
  }
  decode.run(dyn, decoder)
}
