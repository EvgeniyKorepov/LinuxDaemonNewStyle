# LinuxDaemonNewStyle
Linux Daemon new style

https://www.freedesktop.org/software/systemd/man/daemon.html

Example :
```
program DaemonNewStyleTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.SyncObjs,
  Posix.Stdlib,
  Posix.SysStat,
  Posix.SysTypes,
  Posix.Unistd,
  Posix.Signal,
  Posix.Fcntl,
  Posix.Syslog in 'Posix.Syslog.pas',
  UnitDaemonNewStyle in 'UnitDaemonNewStyle.pas';

var
  AEvent : TEventType;

begin
  if ParamCount = 0 then
  begin
    syslog(LOG_ERR, 'No parameters');
    ExitCode := EXIT_FAILURE;
    exit;
  end;

  if ParamStr(1).ToLower.Equals('stop') then
  begin
    if Daemon.Stop(30) then
      ExitCode := EXIT_SUCCESS
    else
      ExitCode := EXIT_FAILURE;
    exit;
  end;
  if ParamStr(1).ToLower.Equals('reload') then
  begin
    if Daemon.Reload() then
      ExitCode := EXIT_SUCCESS
    else
      ExitCode := EXIT_FAILURE;
    exit;
  end;

  if not ParamStr(1).ToLower.Equals('start') then
  begin
    syslog(LOG_ERR, 'Unknow parameters');
    ExitCode := EXIT_FAILURE;
    exit;
  end;

  syslog(LOG_NOTICE, 'main START');
  while Daemon.IsRunning do
  begin
    syslog(LOG_NOTICE, 'main LOOP');
    Daemon.Execute(AEvent);
    if AEvent <> TEventType.None then
      syslog(LOG_NOTICE, 'main Daemon receive signal');
    case AEvent of
      TEventType.Start :
      begin
        syslog(LOG_NOTICE, 'main Event START');
      end;
      TEventType.Reload :
      begin
        // Reload config
        syslog(LOG_NOTICE, 'main Event RELOAD');
      end;
      TEventType.Stop :
      begin
        syslog(LOG_NOTICE, 'main Event STOP');
        ExitCode := EXIT_SUCCESS;
        Sleep(10); // simulate destroy delay
        break;
      end;
    end;
    Sleep(1000);
  end;
end.

```
