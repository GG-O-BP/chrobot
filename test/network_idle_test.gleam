import chrobot
import chrobot/chrome
import chrobot/network_idle
import gleeunit/should
import mock_server
import simplifile as file
import test_utils

pub fn network_idle_start_stop_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)

  let assert Ok(page) = chrobot.open(browser, "about:blank", 10_000)

  let listener = network_idle.start(page) |> should.be_ok()
  network_idle.stop(listener)
}

pub fn network_idle_defer_stop_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)

  let assert Ok(page) = chrobot.open(browser, "about:blank", 10_000)
  let assert Ok(listener) = network_idle.start(page)
  use <- network_idle.defer_stop(listener)

  Nil
}

pub fn network_idle_wait_for_idle_test() {
  mock_server.start()
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)

  let assert Ok(idle_html) = file.read("test_assets/network_idle_test.html")
  let assert Ok(page) = chrobot.create_page(browser, idle_html, 10_000)

  let assert Ok(listener) = network_idle.start(page)
  use <- network_idle.defer_stop(listener)

  // Wait for network to become idle after the staggered fetches
  network_idle.wait_for_idle(listener, quiet_ms: 500, time_out: 10_000)
  |> should.be_ok()

  // Verify all fetches completed
  should.be_ok(chrobot.await_selector(page, "#status"))
}

pub fn network_idle_wait_for_idle_timeout_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)

  let assert Ok(page) = chrobot.open(browser, "about:blank", 10_000)
  let assert Ok(listener) = network_idle.start(page)
  use <- network_idle.defer_stop(listener)

  // With quiet_ms=500 and timeout=1, should timeout immediately
  let result = network_idle.wait_for_idle(listener, quiet_ms: 500, time_out: 1)

  case result {
    Error(chrome.ChromeAgentTimeout) -> Nil
    _ -> should.fail()
  }
}
