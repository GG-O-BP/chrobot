//// Session persistence module for saving and restoring browser session state.
//// Provides functionality similar to Playwright's `storageState` API.
////
//// Usage:
//// ```gleam
//// // Save session
//// let assert Ok(state) = session.save(page)
//// let assert Ok(Nil) = session.save_to_file(state, "session.json")
////
//// // Restore session
//// let assert Ok(state) = session.load_from_file("session.json")
//// let assert Ok(Nil) = session.restore(page, state)
//// ```

import chrobot
import chrobot/chrome
import chrobot/protocol/network
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import simplifile

/// Session state containing cookies and per-origin storage data.
pub type SessionState {
  SessionState(cookies: List(network.Cookie), origins: List(OriginStorage))
}

/// Storage data for a single origin.
pub type OriginStorage {
  OriginStorage(
    origin: String,
    local_storage: List(StorageEntry),
    session_storage: List(StorageEntry),
  )
}

/// A key-value storage entry.
pub type StorageEntry {
  StorageEntry(name: String, value: String)
}

/// Errors that can occur during session operations.
pub type SessionError {
  FileError(simplifile.FileError)
  JsonError
  BrowserError(chrome.RequestError)
}

/// Capture the current session state from a page (cookies + storage).
pub fn save(page: chrobot.Page) -> Result(SessionState, SessionError) {
  let caller = chrobot.page_caller(page)

  // Get all cookies
  use cookies_response <- result.try(
    network.get_cookies(caller, urls: option.None)
    |> result.map_error(BrowserError),
  )

  // Get localStorage and sessionStorage via JS
  use storage_json <- result.try(
    chrobot.eval_to_value(
      on: page,
      js: "JSON.stringify({
        origin: window.location.origin,
        localStorage: Object.entries(localStorage).map(([k,v]) => ({name:k, value:v})),
        sessionStorage: Object.entries(sessionStorage).map(([k,v]) => ({name:k, value:v}))
      })",
    )
    |> result.try(fn(remote_object) {
      chrobot.as_value(Ok(remote_object), decode.string)
    })
    |> result.map_error(BrowserError),
  )

  // Parse the storage JSON
  use origin_storage <- result.try(
    json.parse(storage_json, decode_origin_storage())
    |> result.replace_error(JsonError),
  )

  let origins = case origin_storage.origin {
    // Skip empty/null origins (e.g. about:blank)
    "" -> []
    _ -> [origin_storage]
  }

  Ok(SessionState(cookies: cookies_response.cookies, origins: origins))
}

/// Restore session state to a page (cookies + storage).
pub fn restore(
  page: chrobot.Page,
  state: SessionState,
) -> Result(Nil, SessionError) {
  let caller = chrobot.page_caller(page)

  // Restore cookies
  let cookie_params = list.map(state.cookies, cookie_to_param)
  case cookie_params {
    [] -> Ok(Nil)
    params ->
      network.set_cookies(caller, cookies: params)
      |> result.map(fn(_) { Nil })
      |> result.map_error(BrowserError)
  }
  |> result.try(fn(_) {
    // Restore storage for matching origin
    use origin_data <- result.try(
      chrobot.eval_to_value(on: page, js: "window.location.origin")
      |> result.try(fn(ro) { chrobot.as_value(Ok(ro), decode.string) })
      |> result.map_error(BrowserError),
    )

    let matching_origins =
      list.filter(state.origins, fn(o) { o.origin == origin_data })

    case matching_origins {
      [] -> Ok(Nil)
      [origin, ..] -> {
        let local_js =
          build_storage_restore_js("localStorage", origin.local_storage)
        let session_js =
          build_storage_restore_js("sessionStorage", origin.session_storage)

        use _ <- result.try(
          chrobot.eval(on: page, js: local_js)
          |> result.map(fn(_) { Nil })
          |> result.map_error(BrowserError),
        )
        chrobot.eval(on: page, js: session_js)
        |> result.map(fn(_) { Nil })
        |> result.map_error(BrowserError)
      }
    }
  })
}

/// Save session state to a JSON file.
pub fn save_to_file(
  state: SessionState,
  path: String,
) -> Result(Nil, SessionError) {
  let json_string = encode_session_state(state) |> json.to_string()
  simplifile.write(to: path, contents: json_string)
  |> result.map_error(FileError)
}

/// Load session state from a JSON file.
pub fn load_from_file(path: String) -> Result(SessionState, SessionError) {
  use contents <- result.try(
    simplifile.read(from: path)
    |> result.map_error(FileError),
  )
  json.parse(contents, decode_session_state())
  |> result.replace_error(JsonError)
}

// --- Internal helpers ---

fn cookie_to_param(cookie: network.Cookie) -> network.CookieParam {
  network.CookieParam(
    name: cookie.name,
    value: cookie.value,
    url: option.None,
    domain: option.Some(cookie.domain),
    path: option.Some(cookie.path),
    secure: option.Some(cookie.secure),
    http_only: option.Some(cookie.http_only),
    same_site: cookie.same_site,
    expires: case cookie.session {
      True -> option.None
      False -> option.Some(network.TimeSinceEpoch(cookie.expires))
    },
  )
}

fn build_storage_restore_js(
  storage_name: String,
  entries: List(StorageEntry),
) -> String {
  let set_statements =
    list.map(entries, fn(entry) {
      storage_name
      <> ".setItem("
      <> json.to_string(json.string(entry.name))
      <> ", "
      <> json.to_string(json.string(entry.value))
      <> ");"
    })
    |> list.fold("", fn(acc, s) { acc <> s })

  storage_name <> ".clear();" <> set_statements
}

fn encode_session_state(state: SessionState) -> json.Json {
  json.object([
    #("cookies", json.array(state.cookies, network.encode__cookie)),
    #("origins", json.array(state.origins, encode_origin_storage)),
  ])
}

fn encode_origin_storage(origin: OriginStorage) -> json.Json {
  json.object([
    #("origin", json.string(origin.origin)),
    #("localStorage", json.array(origin.local_storage, encode_storage_entry)),
    #(
      "sessionStorage",
      json.array(origin.session_storage, encode_storage_entry),
    ),
  ])
}

fn encode_storage_entry(entry: StorageEntry) -> json.Json {
  json.object([
    #("name", json.string(entry.name)),
    #("value", json.string(entry.value)),
  ])
}

fn decode_session_state() -> decode.Decoder(SessionState) {
  use cookies <- decode.field("cookies", decode.list(network.decode__cookie()))
  use origins <- decode.field(
    "origins",
    decode.list(decode_origin_storage()),
  )
  decode.success(SessionState(cookies: cookies, origins: origins))
}

fn decode_origin_storage() -> decode.Decoder(OriginStorage) {
  use origin <- decode.field("origin", decode.string)
  use local_storage <- decode.field(
    "localStorage",
    decode.list(decode_storage_entry()),
  )
  use session_storage <- decode.field(
    "sessionStorage",
    decode.list(decode_storage_entry()),
  )
  decode.success(OriginStorage(
    origin: origin,
    local_storage: local_storage,
    session_storage: session_storage,
  ))
}

fn decode_storage_entry() -> decode.Decoder(StorageEntry) {
  use name <- decode.field("name", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(StorageEntry(name: name, value: value))
}
