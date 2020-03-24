unit UnitDaemonNewStyle;

interface
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.SyncObjs,
  Posix.Stdlib,
  Posix.SysStat,
  Posix.SysTypes,
  Posix.Unistd,
  Posix.Signal,
  Posix.Fcntl,
  Posix.Syslog;

const
  // Missing from linux/StdlibTypes.inc !!! <stdlib.h>
  EXIT_FAILURE = 1;
  EXIT_SUCCESS = 0;

type

  TEventType = (
    None,
    Start,
    Reload,
    Stop
  );

  TDaemonNewStyle = class(TObject)
  private
    FFileName : String;
    FPIDFilePath : String;
    FPID: pid_t;
    FQueueSignals : TThreadedQueue<Integer>;
    FIsDaemon : Boolean;
    FIsRunning : Boolean;
    FIsFirstLoop : Boolean;
    function WritePIDFile() : boolean;
    function ReadPIDFile(out APID : Integer) : Boolean;
    function DeletePIDFile() : boolean;
  protected
  public
    constructor Create();
    destructor Destroy; override;

    function Reload() : Boolean;
    function Stop(const ATimeoutSec : Integer = 30) : Boolean;

    procedure Execute(out ATEvent : TEventType);
    property IsRunning : Boolean read FIsRunning;
  end;

var
  Daemon : TDaemonNewStyle;

implementation

var
  QueueSignals : TThreadedQueue<Integer>;

procedure HandleSignals(SigNum: Integer); cdecl;
var ASigNum : Integer;
begin
  if Assigned(QueueSignals) then
  begin
    ASigNum := SigNum;
    QueueSignals.PushItem(ASigNum);
  end;
end;

constructor TDaemonNewStyle.Create();
begin
  inherited Create();
  FQueueSignals := QueueSignals;
  FIsDaemon := False;
  FIsRunning := True;
  FIsFirstLoop := True;

  FFileName := TPath.GetFileName(ParamStr(0));
  FPIDFilePath := '/run/' + TPath.ChangeExtension(FFileName, '.pid');

  // Catch, ignore and handle signals
  signal(SIGCHLD, TSignalHandler(SIG_IGN));
  signal(SIGINT,  HandleSignals);
  signal(SIGHUP,  HandleSignals);
  signal(SIGTERM, HandleSignals);
  signal(SIGQUIT, HandleSignals);

  FPID := getpid();

  // syslog() will call openlog() with no arguments if the log is not currently open.
  syslog(LOG_NOTICE, '------------------------------------------------------------------');
  syslog(LOG_NOTICE, 'TDaemonNewStyle.Create() pid: ' + FPID.ToString);
end;

destructor TDaemonNewStyle.Destroy;
begin
  if FIsDaemon then
  begin
    DeletePIDFile();
    syslog(LOG_NOTICE, 'TDaemonNewStyle.Destroy() - daemon pid: ' + FPID.ToString);
  end
  else
    syslog(LOG_NOTICE, 'TDaemonNewStyle.Destroy() - process pid: ' + FPID.ToString);
  closelog();
  inherited Destroy;
end;

procedure TDaemonNewStyle.Execute(out ATEvent : TEventType);
var AQueueSize : Integer;
    ASignalNum : Integer;
begin
  ATEvent := TEventType.None;
  if FIsFirstLoop then
  begin
    FIsFirstLoop := False;
    FIsDaemon := True;
    ATEvent := TEventType.Start;
    //  syslog(LOG_NOTICE, 'daemon pid : ' + FPID.ToString);
    WritePIDFile();
    syslog(LOG_NOTICE, 'daemon started');
    exit;
  end;
  ASignalNum := 0;
  if QueueSignals.PopItem(AQueueSize, ASignalNum) = System.SyncObjs.TWaitResult.wrSignaled then
  begin
    case ASignalNum of
      SIGINT :
      begin
        syslog(LOG_NOTICE, 'daemon receive signal SIGINT');
      end;
      SIGHUP :
      begin
        ATEvent := TEventType.Reload;
        // Reload config
        syslog(LOG_NOTICE, 'daemon receive signal SIGHUP');
      end;
      SIGTERM :
      begin
        FIsRunning :=False;
        ATEvent := TEventType.Stop;
        syslog(LOG_NOTICE, 'daemon receive signal SIGTERM');
      end;
      SIGQUIT :
      begin
        FIsRunning :=False;
        ATEvent := TEventType.Stop;
        syslog(LOG_NOTICE, 'daemon receive signal SIGQUIT');
      end;
    end;
  end;
end;

function TDaemonNewStyle.WritePIDFile() : boolean;
begin
  Result := False;
  try
    TFile.WriteAllText(FPIDFilePath, FPID.ToString + #10);
  except
    on E : Exception do
    begin
      syslog(LOG_ERR, 'error create PID file ' + FPIDFilePath + ' : ' + E.ClassName + ': ' + E.Message);
      exit;
    end;
  end;
  syslog(LOG_NOTICE, 'succseful write PID to file ' + FPIDFilePath);
  Result := True;
end;

function TDaemonNewStyle.ReadPIDFile(out APID : Integer) : Boolean;
var APIDString : String;
begin
  Result := False;
  if not TFile.Exists(FPIDFilePath) then
  begin
    Writeln('PID file ' + FPIDFilePath + ' not found. Daemon not runneng?');
    exit;
  end;
  try
    APIDString := TFile.ReadAllText(FPIDFilePath).Trim;
    if not TryStrToInt(APIDString, APID) then
      exit;
  except
    on E : Exception do
    begin
      Writeln('Failed read from PID file ' + FPIDFilePath + ' : ' + E.ClassName + ': ' + E.Message);
      exit;
    end;
  end;
  Result := True;
end;

function TDaemonNewStyle.DeletePIDFile() : boolean;
begin
  Result := False;
  try
    if TFile.Exists(FPIDFilePath) then
    begin
      TFile.Delete(FPIDFilePath);
      syslog(LOG_NOTICE, 'succseful delete PID file ' + FPIDFilePath);
    end
    else
      syslog(LOG_NOTICE, 'PID file ' + FPIDFilePath + ' not found');
  except
    on E : Exception do
    begin
      syslog(LOG_ERR, 'error delete PID file ' + FPIDFilePath + ' : ' + E.ClassName + ': ' + E.Message);
      exit;
    end;
   end;
  Result := True;
end;

function TDaemonNewStyle.Stop(const ATimeoutSec : Integer = 30) : Boolean;
var APID : Integer;
    ACounter : Integer;
begin
  Result := False;
  if Not ReadPIDFile(APID) then
    exit;

  kill(APID, SIGTERM);

  ACounter := ATimeoutSec * 10;
  while TFile.Exists(FPIDFilePath) do
  begin
    if ACounter <= 0 then
    begin
      Writeln('failed to stop');
      exit;
    end;
    Sleep(100);
    Dec(ACounter);
  end;
  Writeln('succseful stoped');
  Result := True;
end;

function TDaemonNewStyle.Reload() : Boolean;
var APID : Integer;
begin
  Result := False;
  if Not ReadPIDFile(APID) then
    exit;

  kill(APID, SIGHUP);

  Writeln('Send reload signal');
  Result := True;
end;

initialization

  QueueSignals := TThreadedQueue<Integer>.Create(10,1000, 100);
  Daemon := TDaemonNewStyle.Create();

finalization

  if Assigned(Daemon) then
    Daemon.Free;
  if Assigned(QueueSignals) then
    QueueSignals.Free;

end.
