{
  by Agmcz
  10/4/2019 11:45:21 PM
}

unit uMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, PsAPI, uCheckASLR;

type
  TForm1 = class(TForm)
    Edit1: TEdit;
    Button1: TButton;
    OpenDialog1: TOpenDialog;
    RadioGroup1: TRadioGroup;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

function GetModuleBaseAddress(ProcessID: Cardinal; MName: string): Pointer;
  function AnsiCompareText(const S1, S2: string): Integer;
  begin
    Result := CompareString(LOCALE_USER_DEFAULT, NORM_IGNORECASE, PChar(S1), Length(S1), PChar(S2), Length(S2)) - 2;
  end;
var
  Modules: array of HMODULE;
  cbNeeded, i: Cardinal;
  ModuleInfo: TModuleInfo;
  ModuleName: array[0..MAX_PATH] of Char;
  PHandle: THandle;
begin
  Result := nil;
  SetLength(Modules, 1024);
  PHandle := OpenProcess(PROCESS_QUERY_INFORMATION + PROCESS_VM_READ, False, ProcessID);
  if (PHandle <> 0) then
  begin
    EnumProcessModules(PHandle, @Modules[0], 1024 * SizeOf(HMODULE), cbNeeded); //Getting the enumeration of modules
    SetLength(Modules, cbNeeded div SizeOf(HMODULE)); //Setting the number of modules
    for i := 0 to Length(Modules) - 1 do //Start the loop
    begin
      GetModuleBaseName(PHandle, Modules[i], ModuleName, SizeOf(ModuleName)); //Getting the name of module
      if AnsiCompareText(MName, ModuleName) = 0 then //If the module name match with the name of module we are looking for...
      begin
        GetModuleInformation(PHandle, Modules[i], @ModuleInfo, SizeOf(ModuleInfo)); //Get the information of module
        Result := ModuleInfo.lpBaseOfDll; //Return the information we want (The image base address)
        CloseHandle(PHandle);
        Exit;
      end;
    end;
  end;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  PI: TProcessInformation;
  SI: TStartupInfo;
  bASLR: Boolean;
  pMod: Pointer;
begin
  if OpenDialog1.Execute then
  begin
    case RadioGroup1.ItemIndex of
      0:
        begin
         CheckASLR(OpenDialog1.FileName, bASLR);
         if bASLR then
           MessageBox(Handle, 'ASLR Enabled.', 'ASLR', 64)
         else
           MessageBox(Handle, 'ASLR Disabled!', 'ASLR', 48);
        end;
      1:
        begin
          FillChar(SI, SizeOf(SI), #0);
          if CreateProcess(PChar(OpenDialog1.FileName), nil, nil, nil, True, 0, nil, nil, SI, PI) then
          begin
            Sleep(500);
            pMod := GetModuleBaseAddress(PI.dwProcessId, 'user32.dll' {or ExtractFilePath(ParamStr(0))});
            CheckASLR(PI.hProcess, pMod, bASLR);
            TerminateProcess(PI.hProcess, 0);
            CloseHandle(PI.hProcess);
            CloseHandle(PI.hThread);
            if bASLR then
              MessageBox(Handle, 'ASLR Enabled.', 'ASLR', 64)
            else
              MessageBox(Handle, 'ASLR Disabled!', 'ASLR', 48);
          end
          else
            MessageBox(Handle, PChar('Unable to run ' + ExtractFileName(ParamStr(0))), 'Warning', 48);
        end;
      2:
        begin
          FillChar(SI, SizeOf(SI), #0);
          if CreateProcess(PChar(OpenDialog1.FileName), nil, nil, nil, True, CREATE_SUSPENDED, nil, nil, SI, PI) then
          begin
            CheckASLR(PI.dwProcessId, bASLR);
            TerminateProcess(PI.hProcess, 0);
            CloseHandle(PI.hProcess);
            CloseHandle(PI.hThread);
            if bASLR then
              MessageBox(Handle, 'ASLR Enabled.', 'ASLR', 64)
            else
              MessageBox(Handle, 'ASLR Disabled!', 'ASLR', 48);
          end
          else
            MessageBox(Handle, PChar('Unable to run ' + ExtractFileName(ParamStr(0))), 'Warning', 48);
        end;
      3:
        begin
          FillChar(SI, SizeOf(SI), #0);
          if CreateProcess(PChar(OpenDialog1.FileName), nil, nil, nil, True, CREATE_SUSPENDED, nil, nil, SI, PI) then
          begin
            bASLR := CheckASLR(PI.hProcess);
            TerminateProcess(PI.hProcess, 0);
            CloseHandle(PI.hProcess);
            CloseHandle(PI.hThread);
            if bASLR then
              MessageBox(Handle, 'ASLR Enabled.', 'ASLR', 64)
            else
              MessageBox(Handle, 'ASLR Disabled!', 'ASLR', 48);
          end
          else
            MessageBox(Handle, PChar('Unable to run ' + ExtractFileName(ParamStr(0))), 'Warning', 48);
        end;
    end;
  end;
end;

end.
