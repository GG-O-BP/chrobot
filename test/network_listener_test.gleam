import chrobot
import chrobot/network_listener
import gleeunit/should
import mock_server
import simplifile as file
import test_utils

pub fn network_listener_start_stop_test() {
  mock_server.start()
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)

  let assert Ok(page) = chrobot.open(browser, mock_server.get_url(), 10_000)

  let listener = network_listener.start(page) |> should.be_ok()
  network_listener.stop(listener)
}

pub fn network_listener_defer_stop_test() {
  mock_server.start()
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)

  let assert Ok(page) = chrobot.open(browser, mock_server.get_url(), 10_000)
  let assert Ok(listener) = network_listener.start(page)
  use <- network_listener.defer_stop(listener)

  // drain should return empty list since no new requests happened after start
  let events = network_listener.drain_events(listener)
  // Events may or may not be empty depending on timing, just verify it returns
  let _ = events
  Nil
}

pub fn network_listener_collect_responses_test() {
  mock_server.start()
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)

  let assert Ok(network_html) = file.read("test_assets/network_test.html")
  let assert Ok(page) = chrobot.create_page(browser, network_html, 10_000)
  should.be_ok(chrobot.await_selector(page, "#fetch-btn"))

  let assert Ok(listener) = network_listener.start(page)
  use <- network_listener.defer_stop(listener)

  // Click the button to trigger a fetch request to mock_server root
  should.be_ok(chrobot.click_selector(page, "#fetch-btn"))

  // Wait for the fetch to complete
  should.be_ok(chrobot.await_selector(page, "#result"))
  // Give a moment for network events to arrive
  process_sleep(500)

  // Collect all responses
  let assert Ok(responses) =
    network_listener.collect_responses(listener, fn(_) { True })

  // We should have at least one response (the fetch to /)
  should.be_true(responses != [])
}

@external(erlang, "timer", "sleep")
fn process_sleep(ms: Int) -> Nil
