import chrobot
import chrobot/session
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleeunit/should
import simplifile
import test_utils

pub fn save_test() {
  let browser = test_utils.get_browser_instance()
  let assert Ok(page) =
    chrobot.create_page(
      browser,
      "<html><body><h1>Session Test</h1></body></html>",
      10_000,
    )
  let state = should.be_ok(session.save(page))
  // Should return a valid SessionState (cookies list may be empty on blank page)
  let _ = state.cookies
  let _ = state.origins
  chrobot.quit(browser)
}

pub fn save_restore_cookie_test() {
  let browser = test_utils.get_browser_instance()
  let assert Ok(page) =
    chrobot.create_page(
      browser,
      "<html><body>cookie test</body></html>",
      10_000,
    )

  // Set a cookie via JS
  should.be_ok(chrobot.eval(
    on: page,
    js: "document.cookie = 'testkey=testvalue; path=/'",
  ))

  // Save session
  let state = should.be_ok(session.save(page))

  // Verify cookie was captured
  let has_cookie =
    list.any(state.cookies, fn(c) {
      c.name == "testkey" && c.value == "testvalue"
    })
  should.be_true(has_cookie)

  // Open a new page and restore
  let assert Ok(page2) =
    chrobot.create_page(
      browser,
      "<html><body>restore test</body></html>",
      10_000,
    )

  should.be_ok(session.restore(page2, state))

  // Verify cookie exists on the new page
  let state2 = should.be_ok(session.save(page2))
  let has_cookie2 =
    list.any(state2.cookies, fn(c) {
      c.name == "testkey" && c.value == "testvalue"
    })
  should.be_true(has_cookie2)

  chrobot.quit(browser)
}

pub fn save_to_file_load_from_file_test() {
  let browser = test_utils.get_browser_instance()
  let assert Ok(page) =
    chrobot.create_page(
      browser,
      "<html><body>file test</body></html>",
      10_000,
    )

  // Set a cookie
  should.be_ok(chrobot.eval(
    on: page,
    js: "document.cookie = 'filekey=fileval; path=/'",
  ))

  let state = should.be_ok(session.save(page))

  // Save to file
  let path = "test_session_state.json"
  should.be_ok(session.save_to_file(state, path))

  // Load from file
  let loaded = should.be_ok(session.load_from_file(path))

  // Verify cookies match
  let has_cookie =
    list.any(loaded.cookies, fn(c) {
      c.name == "filekey" && c.value == "fileval"
    })
  should.be_true(has_cookie)

  // Cleanup
  let _ = simplifile.delete(path)
  chrobot.quit(browser)
}

pub fn restore_storage_test() {
  let browser = test_utils.get_browser_instance()
  let assert Ok(page) =
    chrobot.create_page(
      browser,
      "<html><body>storage test</body></html>",
      10_000,
    )

  // Set localStorage
  should.be_ok(chrobot.eval(
    on: page,
    js: "localStorage.setItem('storageKey', 'storageValue')",
  ))

  // Save session
  let state = should.be_ok(session.save(page))

  // Verify storage was captured
  let has_storage =
    list.any(state.origins, fn(o) {
      list.any(o.local_storage, fn(e) {
        e.name == "storageKey" && e.value == "storageValue"
      })
    })
  should.be_true(has_storage)

  // Open new page and restore
  let assert Ok(page2) =
    chrobot.create_page(
      browser,
      "<html><body>restore storage</body></html>",
      10_000,
    )

  should.be_ok(session.restore(page2, state))

  // Verify localStorage was restored
  let result =
    chrobot.eval_to_value(
      on: page2,
      js: "localStorage.getItem('storageKey')",
    )
    |> result.try(fn(ro) { chrobot.as_value(Ok(ro), decode.string) })
  should.equal(should.be_ok(result), "storageValue")

  chrobot.quit(browser)
}
