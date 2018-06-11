unit uCheckASLR;

{*********************************************************************************************
* Delphi Pascal unit: uCheckASLR                                                             *
* check if ASLR is enabled for a process                                                     *
* can check process from disk or memory                                                      *
* work with 32bits and 64 bits                                                               *
* coded using delphi 7                                                                       *
* Inspired by stackoverflow talk                                                             *
* https://stackoverflow.com/questions/47105480/how-to-check-if-aslr-is-enabled-for-a-process *
**********************************************************************************************
* Written by Agmcz                                                                            *
* Date: 2018-06-10                                                                           *
*********************************************************************************************}

interface

uses
  Windows;

type
  NTSTATUS = ULONG;
  PVOID = Pointer;
  HANDLE = THANDLE;  

function CheckASLR(const FileName: WideString; out bASLR: Boolean): NTSTATUS; overload;
function CheckASLR(hProcess: HANDLE; hmod: PVOID; out bASLR: Boolean): NTSTATUS; overload;
function CheckASLR(dwProcessId: LongInt; out bASLR: Boolean): NTSTATUS; overload;
function CheckASLR(hProcess: THandle): Boolean; overload; // from PEB

implementation

type
  SIZE_T = Cardinal;
  PLARGE_INTEGER = ^LARGE_INTEGER;

const
  STATUS_SUCCESS = NTSTATUS(0);
  FILE_READ_DATA            = $0001; // file & pipe
  FILE_READ_EA              = $0008; // file & directory
  FILE_READ_ATTRIBUTES      = $0080; // all
  FILE_GENERIC_READ    = STANDARD_RIGHTS_READ or FILE_READ_DATA or
  FILE_READ_ATTRIBUTES or FILE_READ_EA or SYNCHRONIZE;

  FILE_SHARE_VALID_FLAGS = $00000007;
  FILE_SYNCHRONOUS_IO_NONALERT     = $00000020;

  OBJ_CASE_INSENSITIVE = $00000040;

type
  _SECTION_INFORMATION_CLASS = (
    SectionBasicInformation,
    SectionImageInformation);
  SECTION_INFORMATION_CLASS = _SECTION_INFORMATION_CLASS;
  TSectionInformationClass = SECTION_INFORMATION_CLASS;

 TSectionImageInformation  = record
    TransferAddress: Pointer;
    ZeroBits: LongWord;
    MaximumStackSize: LongWord;
    CommittedStackSize: LongWord;
    SubSystemType: LongWord;
    MinorSubsystemVersion: Word;
    MajorSubsystemVersion: Word;
    GpValue: LongWord;
    ImageCharacteristics: Word;
    DllCharacteristics: Word;
    Machine: Word;
    ImageContainsCode: Boolean;
    ImageFlags: Byte;
    LoaderFlags: LongWord;
    ImageFileSize: LongWord;
    CheckSum: LongWord;
  end;

  TIoStatusBlock = packed record
    Status      : NTSTATUS;
    Information : ULONG;
  end;
  IO_STATUS_BLOCK = TIoStatusBlock;
  P_IO_STATUS_BLOCK = ^TIoStatusBlock;

  TUnicodeString = packed record
    Length: WORD;
    MaximumLength: WORD;
    Buffer: PWideChar;
  end;
  PUnicodeString = ^TUnicodeString;
  TUNICODE_STRING = TUnicodeString;
  UNICODE_STRING = TUnicodeString;
  PUNICODE_STRING = PUnicodeString;

  POBJECT_ATTRIBUTES = ^OBJECT_ATTRIBUTES;
  OBJECT_ATTRIBUTES = packed record
    Length: ULONG;
    RootDirectory: THandle;
    ObjectName: PUNICODE_STRING;
    Attributes: ULONG;
    SecurityDescriptor: PVOID;        // Points to type SECURITY_DESCRIPTOR
    SecurityQualityOfService: PVOID;  // Points to type SECURITY_QUALITY_OF_SERVICE
  end;

function NtOpenFile(FileHandle: PHANDLE; DesiredAccess: ACCESS_MASK; ObjectAttributes: POBJECT_ATTRIBUTES; IoStatusBlock: P_IO_STATUS_BLOCK; ShareAccess: ULONG; OpenOptions: ULONG): LongInt; stdcall; external  'ntdll.dll';
function NtCreateSection(SectionHandle: PHANDLE; DesiredAccess: ACCESS_MASK; ObjectAttributes: POBJECT_ATTRIBUTES; SectionSize: PLARGE_INTEGER; Protect: ULONG; Attributes: ULONG; FileHandle: THandle): LongInt; stdcall; external  'ntdll.dll';
function NtClose(Handle : THandle): LongInt; stdcall; external  'ntdll.dll';
function ZwQuerySection(SectionHandle : THandle; SectionInformationClass : SECTION_INFORMATION_CLASS; SectionInformation: PVOID; SectionInformationLength: ULONG; ResultLength: PULONG): LongInt; stdcall; external  'ntdll.dll';
procedure RtlInitUnicodeString(DestinationString: PUNICODE_STRING; SourceString: PWideChar); stdcall; external 'ntdll.dll';

procedure InitializeObjectAttributes(p: POBJECT_ATTRIBUTES; n: PUNICODE_STRING;
  a: ULONG; r: HANDLE; s: PVOID{PSECURITY_DESCRIPTOR});
begin
  p^.Length := SizeOf(OBJECT_ATTRIBUTES);
  p^.RootDirectory := r;
  p^.Attributes := a;
  p^.ObjectName := n;
  p^.SecurityDescriptor := s;
  p^.SecurityQualityOfService := nil;
end;

function ImageDynamicallyRelocated(sii: TSectionImageInformation): Boolean;
asm
  MOVZX EAX, BYTE PTR SS:[sii.ImageFlags]
  SHR AL, 2
  AND EAX, 1
end;

function CheckASLR(const FileName: WideString; out bASLR: Boolean): NTSTATUS;
var
  status: NTSTATUS;
  hFile, hSection: THandle;
  iosb: IO_STATUS_BLOCK;
  oa: OBJECT_ATTRIBUTES;
  us: TUnicodeString;
  sii: TSectionImageInformation;
begin
  RtlInitUnicodeString(@us, PWideChar('\??\' + FileName));
  InitializeObjectAttributes(@oa, @us, OBJ_CASE_INSENSITIVE, 0, nil);
  status := NtOpenFile(@hFile, FILE_GENERIC_READ, @oa, @iosb, FILE_SHARE_VALID_FLAGS, FILE_SYNCHRONOUS_IO_NONALERT);
  if status = STATUS_SUCCESS then
  begin
    status := NtCreateSection(@hSection, SECTION_QUERY, 0, 0, PAGE_READONLY, SEC_IMAGE, hFile);
    NtClose(hFile);
    if status = STATUS_SUCCESS then
    begin
      status := ZwQuerySection(hSection, SectionImageInformation, @sii, sizeof(sii), 0);
      NtClose(hSection);
      if status = STATUS_SUCCESS then
      begin
        bASLR := ImageDynamicallyRelocated(sii);
      end;
    end;
  end;
  Result := status;
end;

type
  _MEMORY_SECTION_NAME = record // Information Class 2
    SectionFileName: UNICODE_STRING;
  end;
  MEMORY_SECTION_NAME = _MEMORY_SECTION_NAME;
  PMEMORY_SECTION_NAME = ^MEMORY_SECTION_NAME;
  TMemorySectionName = MEMORY_SECTION_NAME;
  PMemorySectionName = ^TMemorySectionName;

  _MEMORY_INFORMATION_CLASS = (
    MemoryBasicInformation,
    MemoryWorkingSetList,
    MemorySectionName,
    MemoryBasicVlmInformation);
  MEMORY_INFORMATION_CLASS = _MEMORY_INFORMATION_CLASS;
  TMemoryInformationClass = MEMORY_INFORMATION_CLASS;
  PMemoryInformationClass = ^TMemoryInformationClass;
function NtQueryVirtualMemory(ProcessHandle: THandle; BaseAddress: Pointer;  MemoryInformationClass: TMemoryInformationClass;  MemoryInformation: Pointer;  MemoryInformationLength: ULONG; ReturnLength : PULONG): LongInt; stdcall; external 'ntdll.dll';

function CheckASLR(hProcess: HANDLE; hmod: PVOID; out bASLR: Boolean): NTSTATUS;
var
  cb, rcb: SIZE_T;
  buf: PVOID;
  status: NTSTATUS;
  hFile, hSection: THandle;
  iosb: IO_STATUS_BLOCK;
  oa: OBJECT_ATTRIBUTES;
  sii: TSectionImageInformation;
begin
  cb := 0;
  rcb := MAX_PATH * SizeOf(WCHAR);
  GetMem(buf, rcb);
  status := NtQueryVirtualMemory(hProcess, hmod, MemorySectionName, buf, rcb, @cb);
  if status = STATUS_SUCCESS then
  begin
    InitializeObjectAttributes(@oa, buf, OBJ_CASE_INSENSITIVE, 0, nil);
    status := NtOpenFile(@hFile, FILE_GENERIC_READ, @oa, @iosb, FILE_SHARE_VALID_FLAGS, FILE_SYNCHRONOUS_IO_NONALERT);
    if status = STATUS_SUCCESS then
    begin
      status := NtCreateSection(@hSection, SECTION_QUERY, 0, 0, PAGE_READONLY, SEC_IMAGE, hFile);
      NtClose(hFile);
     if status = STATUS_SUCCESS then
      begin
        status := ZwQuerySection(hSection, SectionImageInformation, @sii, sizeof(sii), 0);
        NtClose(hSection);
        if status = STATUS_SUCCESS then
        begin
          bASLR := ImageDynamicallyRelocated(sii);
        end;
      end;
    end;
    FreeMem(buf);
  end;
  Result := status;
end;

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

type
  PROCESSINFOCLASS = (
    ProcessBasicInformation,
    ProcessQuotaLimits,
    ProcessIoCounters,
    ProcessVmCounters,
    ProcessTimes,
    ProcessBasePriority,
    ProcessRaisePriority,
    ProcessDebugPort,
    ProcessExceptionPort,
    ProcessAccessToken,
    ProcessLdtInformation,
    ProcessLdtSize,
    ProcessDefaultHardErrorMode,
    ProcessIoPortHandlers,
    ProcessPooledUsageAndLimits,
    ProcessWorkingSetWatch,
    ProcessUserModeIOPL,
    ProcessEnableAlignmentFaultFixup,
    ProcessPriorityClass,
    ProcessWx86Information,
    ProcessHandleCount,
    ProcessAffinityMask,
    ProcessPriorityBoost,
    ProcessDeviceMap,
    ProcessSessionInformation,
    ProcessForegroundInformation,
    ProcessWow64Information,
    ProcessImageFileName,
    ProcessLUIDDeviceMapsEnabled,
    ProcessBreakOnTermination,
    ProcessDebugObjectHandle,
    ProcessDebugFlags,
    ProcessHandleTracing,
    ProcessIoPriority,
    ProcessExecuteFlags,
    ProcessTlsInformation,
    ProcessCookie,
    ProcessImageInformation,
    ProcessCycleTime,
    ProcessPagePriority,
    ProcessInstrumentationCallback,
    ProcessThreadStackAllocation,
    ProcessWorkingSetWatchEx,
    ProcessImageFileNameWin32,
    ProcessImageFileMapping,
    ProcessAffinityUpdateMode,
    ProcessMemoryAllocationMode,
    ProcessGroupInformation,
    ProcessTokenVirtualizationEnabled,
    ProcessConsoleHostProcess,
    ProcessWindowInformation,
    MaxProcessInfoClass);

function NtQueryInformationProcess(ProcessHandle: THandle; ProcessInformationClass: PROCESSINFOCLASS; ProcessInformation: Pointer; ProcessInformationLength: ULONG; ReturnLength: PULONG ): LongInt; stdcall; external 'ntdll.dll';
function RtlNtStatusToDosError(Status: NTSTATUS): Integer; stdcall; external 'ntdll.dll';

function CheckASLR(dwProcessId: LongInt; out bASLR: Boolean): NTSTATUS;
var
 hProcess: THandle;
 sii: TSectionImageInformation;
 status: NTSTATUS;
begin
  hProcess := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, dwProcessId);
  if (hProcess <> 0) and (hProcess <> INVALID_HANDLE_VALUE) then
  begin
    status := NtQueryInformationProcess(hProcess, ProcessImageInformation, @sii, SizeOf(sii), 0);
    CloseHandle(hProcess);
    if status = STATUS_SUCCESS then
    begin
      bASLR := ImageDynamicallyRelocated(sii);
      Result := NOERROR;
      Exit;
    end;
    Result := RtlNtStatusToDosError(status);
    Exit;
  end;
  Result := GetLastError;
end;

type
  PProcessBasicInformation = ^TProcessBasicInformation;
  TProcessBasicInformation = record
    ExitStatus: LongInt;
    PebBaseAddress: Pointer;
    AffinityMask: Cardinal;
    BasePriority: LongInt;
    UniqueProcessId: Cardinal;
    InheritedFromUniqueProcessId: Cardinal;
  end;

  PProcessBasicInformation64 = ^TProcessBasicInformation64;
  TProcessBasicInformation64 = record
    ExitStatus: Cardinal;
    Pad1: Cardinal;
    PebBaseAddress: UInt64;
    AffinityMask: UInt64;
    BasePriority: Cardinal;
    Pad2: Cardinal;
    UniqueProcessId: UInt64;
    InheritedFromUniqueProcessId: UInt64;
  end;

  TNtQueryInformationProcess = function(ProcessHandle: THandle; ProcessInformationClass: DWORD {PROCESSINFOCLASS}; ProcessInformation: Pointer; ProcessInformationLength: ULONG; ReturnLength: Pointer): LongInt; stdcall;
  TNtReadVirtualMemory = function(ProcessHandle: THandle; BaseAddress: Pointer; Buffer: Pointer; BufferLength: ULONG; ReturnLength: PULONG): Longint; stdcall;
  TNtWow64ReadVirtualMemory64 = function(ProcessHandle: THandle; BaseAddress: UInt64; Buffer: Pointer; BufferLength: UInt64; ReturnLength: Pointer): LongInt; stdcall;

function Is64OS: LongBool;
asm
  XOR EAX, EAX
  MOV EAX, FS:[$C0]
end;

function ImageDynamicallyRelocated_(BitField: Byte): Boolean;
asm
  CMP AL, 4
  JNE @Else
  SHR AL, 2
  JMP @EndIF
  @Else:
  SHR AL, 3
  @EndIF:
  AND AL, 1
end;

function CheckASLR(hProcess: THandle): Boolean;
var
  PBI: TProcessBasicInformation;
  PBI64: TProcessBasicInformation64;
  BitField: Byte;
  hntdll: HMODULE;
  NtQueryInformationProcess: TNtQueryInformationProcess;
  NtReadVirtualMemory: TNtReadVirtualMemory;
  NtWow64QueryInformationProcess64: TNtQueryInformationProcess;
  NtWow64ReadVirtualMemory64: TNtWow64ReadVirtualMemory64;
begin
  Result := False;
  if (hProcess <> 0) and (hProcess <> INVALID_HANDLE_VALUE) then
  begin
    hntdll := LoadLibrary('ntdll.dll');
    if hntdll <> 0 then
    begin
      if Is64OS then
      begin
        @NtWow64QueryInformationProcess64 := GetProcAddress(hntdll, 'NtWow64QueryInformationProcess64');
        @NtWow64ReadVirtualMemory64 := GetProcAddress(hntdll, 'NtWow64ReadVirtualMemory64');
        if NtWow64QueryInformationProcess64(hProcess, 0{ProcessBasicInformation = 0}, @PBI64, SizeOf(TProcessBasicInformation64), 0) = STATUS_SUCCESS then
        begin
          if NtWow64ReadVirtualMemory64(hProcess, PBI64.PebBaseAddress + 3, @BitField{Peb.BitField}, SizeOf(Byte), 0) = STATUS_SUCCESS then
            Result := ImageDynamicallyRelocated_(BitField);
        end;
      end
      else
      begin
        @NtQueryInformationProcess := GetProcAddress(hntdll, 'NtQueryInformationProcess');
        @NtReadVirtualMemory := GetProcAddress(hntdll, 'NtReadVirtualMemory');
        if NtQueryInformationProcess(hProcess, 0{ProcessBasicInformation = 0}, @PBI, SizeOf(TProcessBasicInformation), 0) = STATUS_SUCCESS then
        begin
          if NtReadVirtualMemory(hProcess, Pointer(DWORD(PBI.PebBaseAddress) + 3), @BitField{Peb.BitField}, SizeOf(Byte), nil) = STATUS_SUCCESS then
            Result := ImageDynamicallyRelocated_(BitField);
        end;
      end;
      FreeLibrary(hntdll);
    end;
  end
end;

end.
