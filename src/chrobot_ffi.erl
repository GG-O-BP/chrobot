-module(chrobot_ffi).
-include_lib("kernel/include/file.hrl").
-export([open_browser_port/2, send_to_port/2, get_arch/0, unzip/2, set_executable/1, run_command/1, get_time_ms/0, get_os_type/0,
         open_browser_port_ws/2, wait_for_ws_url/2, gun_ws_connect/1, gun_ws_send/3, gun_ws_close/1, get_port_os_pid/1, kill_os_process/1,
         find_free_port/0, get_ws_url_via_http/2]).

% ---------------------------------------------------
% RUNTIME
% ---------------------------------------------------

% FFI to interact with the browser via a port from erlang
% since gleam does not really support ports yet.
% module: chrobot/chrome.gleam

% The port is opened with the option "nouse_stdio"
% which makes it use file descriptors 3 and 4 for stdin and stdout
% This is what chrome expects when started with --remote-debugging-pipe.
% A nice side effect of this is that chrome should quit when the pipe is closed,
% avoiding the commmon port-related problem of zombie processes.
open_browser_port(Command, Args) ->
    PortName = {spawn_executable, Command},
    Options = [{args, Args}, binary, nouse_stdio, exit_status],
    try erlang:open_port(PortName, Options) of
        PortId ->
            erlang:link(PortId),
            {ok, PortId}
    catch
        error:Reason -> {error, Reason}
    end.

send_to_port(Port, BinaryString) ->
    try erlang:port_command(Port, BinaryString) of
        true -> {ok, true}
    catch
        error:Reason -> {error, Reason}
    end.

% Open browser port for WebSocket mode.
% Uses stderr_to_stdout so we can read the DevTools WS URL from stdout.
open_browser_port_ws(Command, Args) ->
    PortName = {spawn_executable, Command},
    Options = [{args, Args}, binary, stderr_to_stdout, exit_status],
    try erlang:open_port(PortName, Options) of
        PortId ->
            erlang:link(PortId),
            {ok, PortId}
    catch
        error:Reason -> {error, Reason}
    end.

% Wait for Chrome's WebSocket URL.
% Chrome 146+에서는 stderr에 DevTools URL을 출력하지 않으므로,
% stderr 파싱과 HTTP /json/version 폴링을 동시에 시도한다.
wait_for_ws_url(Port, Timeout) ->
    wait_for_ws_url_loop(Port, Timeout, <<>>, 0).

wait_for_ws_url_loop(Port, Timeout, Buffer, Elapsed) when Elapsed >= Timeout ->
    % 마지막으로 stderr 버퍼 확인
    flush_port_data(Port, Buffer),
    {error, timeout};
wait_for_ws_url_loop(Port, Timeout, Buffer, Elapsed) ->
    % 1) stderr에서 비블로킹으로 데이터 확인
    {NewBuffer, Exited} = flush_port_data(Port, Buffer),
    % stderr에서 URL 찾기
    case re:run(NewBuffer, <<"DevTools listening on (ws://[^\\s\\r\\n]+)">>,
                [{capture, [1], binary}]) of
        {match, [Url]} -> {ok, Url};
        nomatch ->
            case Exited of
                true -> {error, browser_exited};
                false ->
                    % 2) HTTP /json/version 폴링 시도
                    timer:sleep(500),
                    wait_for_ws_url_loop(Port, Timeout, NewBuffer, Elapsed + 500)
            end
    end.

% 포트에서 non-blocking으로 모든 대기 데이터를 읽기
flush_port_data(Port, Buffer) ->
    receive
        {Port, {data, Data}} ->
            flush_port_data(Port, <<Buffer/binary, Data/binary>>);
        {Port, {exit_status, _}} ->
            {Buffer, true}
    after 0 ->
        {Buffer, false}
    end.

% Connect to Chrome DevTools WebSocket endpoint using gun.
gun_ws_connect(WsUrl) ->
    {ok, _} = application:ensure_all_started(gun),
    case uri_string:parse(WsUrl) of
        #{host := Host, port := Port, path := Path} ->
            HostStr = case is_binary(Host) of
                true -> binary_to_list(Host);
                false -> Host
            end,
            PathBin = case is_binary(Path) of
                true -> Path;
                false -> list_to_binary(Path)
            end,
            case gun:open(HostStr, Port, #{protocols => [http]}) of
                {ok, ConnPid} ->
                    case gun:await_up(ConnPid, 5000) of
                        {ok, _} ->
                            StreamRef = gun:ws_upgrade(ConnPid, PathBin, []),
                            receive
                                {gun_upgrade, ConnPid, StreamRef, [<<"websocket">>], _} ->
                                    {ok, {ConnPid, StreamRef}};
                                {gun_response, ConnPid, _, _, Status, _} ->
                                    gun:close(ConnPid),
                                    {error, {ws_upgrade_failed, Status}};
                                {gun_error, ConnPid, StreamRef, Reason} ->
                                    gun:close(ConnPid),
                                    {error, Reason}
                            after 5000 ->
                                gun:close(ConnPid),
                                {error, ws_upgrade_timeout}
                            end;
                        {error, Reason} ->
                            gun:close(ConnPid),
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        _ -> {error, invalid_url}
    end.

% Send a text frame via gun WebSocket.
gun_ws_send(ConnPid, StreamRef, Data) ->
    gun:ws_send(ConnPid, StreamRef, {text, Data}),
    {ok, true}.

% Close a gun connection.
gun_ws_close(ConnPid) ->
    gun:close(ConnPid),
    nil.

% Get the OS process ID of an Erlang port.
get_port_os_pid(Port) ->
    case erlang:port_info(Port, os_pid) of
        {os_pid, Pid} -> {ok, Pid};
        undefined -> {error, not_found}
    end.

% Kill an OS process by PID.
kill_os_process(OsPid) ->
    case os:type() of
        {win32, _} -> os:cmd("taskkill /F /PID " ++ integer_to_list(OsPid));
        _ -> os:cmd("kill -9 " ++ integer_to_list(OsPid))
    end,
    nil.

% Find a free TCP port by binding to port 0 and reading the assigned port.
find_free_port() ->
    {ok, Socket} = gen_tcp:listen(0, []),
    {ok, Port} = inet:port(Socket),
    gen_tcp:close(Socket),
    Port.

% Chrome 146+: HTTP /json/version에서 webSocketDebuggerUrl을 가져온다.
% 500ms 간격으로 폴링, Timeout(ms) 내에 성공하지 못하면 error 반환.
get_ws_url_via_http(DebugPort, Timeout) ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(ssl),
    Url = "http://127.0.0.1:" ++ integer_to_list(DebugPort) ++ "/json/version",
    get_ws_url_via_http_loop(Url, Timeout, 0).

get_ws_url_via_http_loop(_Url, Timeout, Elapsed) when Elapsed >= Timeout ->
    {error, <<"timeout">>};
get_ws_url_via_http_loop(Url, Timeout, Elapsed) ->
    case httpc:request(get, {Url, []}, [{timeout, 3000}], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} ->
            case re:run(Body, <<"\"webSocketDebuggerUrl\"\\s*:\\s*\"(ws://[^\"]+)\"">>,
                        [{capture, [1], binary}]) of
                {match, [WsUrl]} -> {ok, WsUrl};
                nomatch ->
                    timer:sleep(500),
                    get_ws_url_via_http_loop(Url, Timeout, Elapsed + 500)
            end;
        _ ->
            timer:sleep(500),
            get_ws_url_via_http_loop(Url, Timeout, Elapsed + 500)
    end.

% ---------------------------------------------------
% INSTALLER
% ---------------------------------------------------

% Utils for the installer script
% module: chrobot/install.gleam

% Get the architecture of the system
get_arch() ->
    ArchCharlist = erlang:system_info(system_architecture),
    list_to_binary(ArchCharlist).

% Run a shell command and return the output
run_command(Command) ->
    CommandList = binary_to_list(Command),
    list_to_binary(os:cmd(CommandList)).

% Unzip a file to a directory using the erlang stdlib zip module
unzip(ZipFile, DestDir) ->
    ZipFileCharlist = binary_to_list(ZipFile),
    DestDirCharlist = binary_to_list(DestDir),
    try zip:unzip(ZipFileCharlist, [{cwd, DestDirCharlist}]) of
        {ok, _FileList} ->
            {ok, nil};
        {error, _} = Error ->
            Error
    catch
        _:Reason ->
            {error, Reason}
    end.

% Set the executable bit on a file
set_executable(FilePath) ->
    FileInfo = file:read_file_info(FilePath),
    case FileInfo of
        {ok, FI} ->
            NewFI = FI#file_info{mode = 8#755},
            case file:write_file_info(FilePath, NewFI) of
                ok -> {ok, nil};
                {error, _} = Error -> Error
            end;
        {error, Reason} ->
            {error, Reason}
    end.

% ---------------------------------------------------
% UTILITIES
% ---------------------------------------------------

% Miscelaneous utilities
% module: chrobot/internal/utils.gleam

get_time_ms() ->
    os:system_time(millisecond).

get_os_type() ->
    {Family, Name} = os:type(),
    {atom_to_binary(Family), atom_to_binary(Name)}.