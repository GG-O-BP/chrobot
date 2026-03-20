//// Network response event listener for chrobot.
//// Provides a high-level API to subscribe to and collect network responses.

import chrobot
import chrobot/chrome
import chrobot/protocol/network
import gleam/dynamic as d
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option
import gleam/result

/// Network.responseReceived 이벤트를 디코딩한 결과
pub type ResponseReceivedEvent {
  ResponseReceivedEvent(
    request_id: network.RequestId,
    response: network.Response,
  )
}

/// 응답 이벤트 + 본문
pub type ResponseWithBody {
  ResponseWithBody(event: ResponseReceivedEvent, body: String)
}

/// 활성 리스너 핸들
pub opaque type NetworkListener {
  NetworkListener(
    browser: Subject(chrome.Message),
    page: chrobot.Page,
    listener_subject: Subject(d.Dynamic),
  )
}

/// Network 도메인 활성화 + responseReceived 이벤트 리스너 등록
pub fn start(page: chrobot.Page) -> Result(NetworkListener, chrome.RequestError) {
  use _ <- result.try(network.enable(
    chrobot.page_caller(page),
    max_post_data_size: option.None,
  ))
  let listener_subject =
    chrome.add_listener(page.browser, "Network.responseReceived")
  Ok(NetworkListener(
    browser: page.browser,
    page: page,
    listener_subject: listener_subject,
  ))
}

/// 리스너 해제
pub fn stop(listener: NetworkListener) -> Nil {
  chrome.remove_listener(listener.browser, listener.listener_subject)
}

/// use 표현식용 defer 패턴
pub fn defer_stop(listener: NetworkListener, body: fn() -> a) -> a {
  let result = body()
  stop(listener)
  result
}

/// listener_subject에서 현재까지 도착한 이벤트를 모두 꺼내서 디코딩
pub fn drain_events(listener: NetworkListener) -> List(ResponseReceivedEvent) {
  let selector =
    process.new_selector()
    |> process.select(listener.listener_subject)
  drain_loop(selector, [])
}

fn drain_loop(
  selector: process.Selector(d.Dynamic),
  acc: List(ResponseReceivedEvent),
) -> List(ResponseReceivedEvent) {
  case process.selector_receive(from: selector, within: 0) {
    Ok(dyn) -> {
      case decode.run(dyn, decode_response_received_event()) {
        Ok(event) -> drain_loop(selector, [event, ..acc])
        Error(_) -> drain_loop(selector, acc)
      }
    }
    Error(Nil) -> list.reverse(acc)
  }
}

/// drain_events + URL 필터 + get_response_body로 본문까지 수집
pub fn collect_responses(
  listener: NetworkListener,
  filter filter: fn(ResponseReceivedEvent) -> Bool,
) -> Result(List(ResponseWithBody), chrome.RequestError) {
  let events = drain_events(listener)
  let filtered = list.filter(events, filter)
  let caller = chrobot.page_caller(listener.page)
  collect_bodies(caller, filtered, [])
}

fn collect_bodies(
  caller,
  events: List(ResponseReceivedEvent),
  acc: List(ResponseWithBody),
) -> Result(List(ResponseWithBody), chrome.RequestError) {
  case events {
    [] -> Ok(list.reverse(acc))
    [event, ..rest] -> {
      use resp <- result.try(network.get_response_body(
        caller,
        request_id: event.request_id,
      ))
      let with_body = ResponseWithBody(event: event, body: resp.body)
      collect_bodies(caller, rest, [with_body, ..acc])
    }
  }
}

fn decode_response_received_event() -> decode.Decoder(ResponseReceivedEvent) {
  use request_id <- decode.field("requestId", network.decode__request_id())
  use response <- decode.field("response", network.decode__response())
  decode.success(ResponseReceivedEvent(
    request_id: request_id,
    response: response,
  ))
}
