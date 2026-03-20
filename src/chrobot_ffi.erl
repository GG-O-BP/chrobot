-module(chrobot_ffi).
-include_lib("kernel/include/file.hrl").
-export([open_browser_port/2, send_to_port/2, get_arch/0, unzip/2, set_executable/1, run_command/1, get_time_ms/0, get_os_type/0,
         open_browser_port_ws/2, wait_for_ws_url/2, gun_ws_connect/1, gun_ws_send/3, gun_ws_close/1, get_port_os_pid/1, kill_os_process/1]).

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

% Wait for Chrome to print its WebSocket URL on stderr (redirected to stdout).
% Pattern: "DevTools listening on ws://..."
wait_for_ws_url(Port, Timeout) ->
    wait_for_ws_url_loop(Port, Timeout, <<>>).

wait_for_ws_url_loop(Port, Timeout, Buffer) ->
    receive
        {Port, {data, Data}} ->
            Combined = <<Buffer/binary, Data/binary>>,
            case re:run(Combined, <<"DevTools listening on (ws://[^\\s\\r\\n]+)">>,
                        [{capture, [1], binary}]) of
                {match, [Url]} -> {ok, Url};
                nomatch -> wait_for_ws_url_loop(Port, Timeout, Combined)
            end;
        {Port, {exit_status, _}} -> {error, browser_exited}
    after Timeout -> {error, timeout}
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