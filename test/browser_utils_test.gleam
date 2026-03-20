import chrobot
import chrobot/browser_utils
import gleam/string
import gleeunit/should
import simplifile as file
import test_utils

pub fn get_url_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  let url =
    browser_utils.get_url(page)
    |> should.be_ok()

  // create_page uses a data URL or about:blank-like scheme
  { string.length(url) > 0 }
  |> should.be_true()
}

pub fn wait_for_url_success_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  // The URL should already match (it's not empty)
  browser_utils.wait_for_url(
    page: page,
    matching: fn(url) { string.length(url) > 0 },
    time_out: 5000,
  )
  |> should.be_ok()
}

pub fn wait_for_url_timeout_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  // This predicate will never match, so it should timeout
  browser_utils.wait_for_url(
    page: page,
    matching: fn(url) { string.contains(url, "never-match-this") },
    time_out: 500,
  )
  |> should.be_error()
}

pub fn is_visible_true_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  browser_utils.is_visible(page: page, selector: "#visible-element")
  |> should.be_ok()
  |> should.be_true()
}

pub fn is_visible_display_none_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  browser_utils.is_visible(page: page, selector: "#hidden-display")
  |> should.be_ok()
  |> should.be_false()
}

pub fn is_visible_visibility_hidden_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  browser_utils.is_visible(page: page, selector: "#hidden-visibility")
  |> should.be_ok()
  |> should.be_false()
}

pub fn is_visible_opacity_zero_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  browser_utils.is_visible(page: page, selector: "#hidden-opacity")
  |> should.be_ok()
  |> should.be_false()
}

pub fn is_visible_nonexistent_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  browser_utils.is_visible(page: page, selector: "#does-not-exist")
  |> should.be_ok()
  |> should.be_false()
}

pub fn await_visible_test() {
  let browser = test_utils.get_browser_instance()
  use <- chrobot.defer_quit(browser)
  let assert Ok(html) = file.read("test_assets/visibility_test.html")
  let assert Ok(page) = chrobot.create_page(browser, html, 10_000)

  // The delayed-element becomes visible after 200ms
  browser_utils.await_visible(
    page: page,
    selector: "#delayed-element",
    time_out: 5000,
  )
  |> should.be_ok()
  |> should.be_true()
}
