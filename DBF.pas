unit DBF;

////////////////////////////////////////////////////////////////////////////////
//
// Author: Jaap Baak
// https://github.com/transportmodelling/Utils
//
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
interface
////////////////////////////////////////////////////////////////////////////////

Uses
  Classes, SysUtils, Variants, Generics.Collections, ArrayBld;

Type
  TDBFField = record
  private
    FFieldName: String;
    FFieldType: Char;
    FFieldLength,FDecimalCount: Byte;
    FTruncate: Boolean;
    FieldValue: Variant;
    FieldFormat: String;
    Procedure SetFieldName(Value: string);
    Procedure SetFieldType(Value: Char);
    Procedure SetFieldLength(Value: Byte);
    Procedure SetDecimalCount(Value: Byte);
    Procedure SetFieldFormat;
    Procedure Validate;
  public
    Constructor Create(const FieldName: String; const FieldType: Char;
                       const FieldLength,DecimalCount: Byte;
                       const Truncate: Boolean = false);
  public
    Property FieldName: String read FFieldName write SetFieldName;
    Property FieldType: Char read FFieldType write SetFieldType;
    Property FieldLength: Byte read FFieldLength write SetFieldLength;
    Property DecimalCount: Byte read FDecimalCount write SetDecimalCount;
    Property Truncate: Boolean read FTruncate;
  end;

  TDBFFile = Class
  private
    FFileName: string;
    FFieldCount,FRecordCount: Integer;
    FFields: TArray<TDBFField>;
    FileStream: TBufferedFileStream;
    FormatSettings: TFormatSettings;
    Function GetFieldNames(Field: Integer): String;
    Function GetFieldTypes(Field: Integer): Char;
    Function GetFieldLength(Field: Integer): Byte;
    Function GetDecimalCount(Field: Integer): Byte;
    Function GetPairs(Field: Integer): TPair<String,Variant>; overload;
    Function GetFieldValues(Field: Integer): Variant;
  public
    Constructor Create;
    Function IndexOf(const FieldName: String; const MustExist: Boolean = false): Integer;
    Function GetFields: TArray<TDBFField>; overload;
    Function GetFields(const FieldNames: array of String): TArray<TDBFField>; overload;
    Function GetValues: TArray<Variant>;
    Function GetPairs: TArray<TPair<String,Variant>>; overload;
  public
    Property FileName: String read FFileName;
    Property FieldCount: Integer read FFieldCount;
    Property RecordCount: Integer read FRecordCount;
    Property FieldNames[Field: Integer]: String read GetFieldNames;
    Property FieldTypes[Field: Integer]: Char read GetFieldTypes;
    Property FieldLength[Field: Integer]: Byte read GetFieldLength;
    Property DecimalCount[Field: Integer]: Byte read GetDecimalCount;
    Property Pairs[Field: Integer]: TPair<String,Variant> read GetPairs;
    Property FieldValues[Field: Integer]: Variant read GetFieldValues; default;
  end;

  TDBFReader = Class(TDBFFile)
  private
    FRecordIndex: Integer;
    FileReader: TBinaryReader;
    Version: Byte;
  public
    Constructor Create(const FileName: String);
    Function NextRecord: Boolean; overload;
    Function NextRecord(var Values: array of Variant): Boolean; overload;
    Destructor Destroy; override;
  public
    Property RecordIndex: Integer read FRecordIndex;
  end;

  TDBFWriter = Class(TDBFFile)
  private
    FileWriter: TBinaryWriter;
    Procedure SetFieldValues(Field: Integer; Value: Variant);
  public
    Constructor Create(const FileName: String; const Fields: array of TDBFField); overload;
    Constructor Create(const FileName: String; const DBFFile: TDBFFile); overload;
    Procedure AppendRecord; overload;
    Procedure AppendRecord(const Values: array of Variant); overload;
    Destructor Destroy; override;
  public
    Property FieldValues[Field: Integer]: Variant read GetFieldValues write SetFieldValues; default;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Constructor TDBFField.Create(const FieldName: String; const FieldType: Char;
                             const FieldLength,DecimalCount: Byte;
                             const Truncate: Boolean = false);
begin
  SetFieldName(FieldName);
  SetFieldType(FieldType);
  SetFieldLength(FieldLength);
  SetDecimalCount(DecimalCount);
  FTruncate := Truncate;
end;

Procedure TDBFField.SetFieldName(Value: string);
begin
  Value := Trim(Uppercase(Value));
  if (Value <> '') and (Length(Value) <= 10) then
  begin
    FFieldName := Value;
    for var Chr := 1 to Length(Value) do
    if Value[Chr] in ['A'..'Z'] then Continue else
    if Value[Chr] in ['0'..'9'] then Continue else
    if Value[Chr] <> '_' then raise Exception.Create('Invalid Field Name ' + Value);
  end else
    raise Exception.Create('Invalid Field Name ' + Value);
end;

Procedure TDBFField.SetFieldType(Value: Char);
begin
  if Value <> FFieldType then
  begin
    FFieldType := Value;
    case Value of
      'C': begin
             FFieldLength := 10;
             FDecimalCount := 0;
           end;
      'D': begin
             FFieldLength := 8;
             FDecimalCount := 0;
           end;
      'L': begin
             FFieldLength := 1;
             FDecimalCount := 0;
           end;
      'F','N':
           begin
             FFieldLength := 10;
             FDecimalCount := 0;
           end;
      'I': begin
             FFieldLength := 4;
             FDecimalCount := 0;
           end;
      'O': begin
             FFieldLength := 8;
             FDecimalCount := 0;
           end;
      else raise Exception.Create('Unsupported Field Type ' + Value);
    end;
  end;
end;

Procedure TDBFField.SetFieldLength(Value: Byte);
begin
  if Value <> FFieldLength then
  begin
    FFieldLength := Value;
    if Value > 0 then
      case FFieldType of
        'C': if Value > 254 then raise Exception.Create('Invalid Field Length');
        'D': if Value <> 8 then raise Exception.Create('Invalid Field Length');
        'L': if Value <> 1 then raise Exception.Create('Invalid Field Length');
        'F','N':
             begin
               if Value > 20 then raise Exception.Create('Invalid Field Length') else
               if (FDecimalCount > 0) and (Value < FDecimalCount+2) then raise Exception.Create('Invalid Field Length');
               SetFieldFormat;
             end;
        'I': if Value <> 4 then raise Exception.Create('Invalid Field Length');
        'O': if Value <> 8 then raise Exception.Create('Invalid Field Length');
      end
    else
      raise Exception.Create('Invalid Field Length');
  end;
end;

Procedure TDBFField.SetDecimalCount(Value: Byte);
begin
  if Value <> FDecimalCount then
  begin
    FDecimalCount := Value;
    if FFieldType in ['F','N'] then
    begin
      SetFieldFormat;
      if Value > FFieldlength-2 then raise Exception.Create('Field Length too small');
    end else
    begin
      if Value <> 0 then raise Exception.Create('Invalid Decimal Count');
    end;
  end;
end;

Procedure TDBFField.SetFieldFormat;
begin
  if FDecimalCount = 0 then FieldFormat := '0' else
  begin
    FieldFormat := '0.';
    for var Decimal := 1 to FDecimalCount do FieldFormat := FieldFormat + '#';
  end;
end;

Procedure TDBFField.Validate;
begin
  if (FFieldName = '') or (FFieldType = #0) then raise Exception.Create('Uninitialized DBF Field');
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TDBFFile.Create;
begin
  inherited Create;
  FormatSettings.DecimalSeparator := '.';
end;

Function TDBFFile.GetFieldNames(Field: Integer): String;
begin
  Result := FFields[Field].FFieldName;
end;

Function TDBFFile.GetFieldTypes(Field: Integer): Char;
begin
  Result := FFields[Field].FFieldType;
end;

Function TDBFFile.GetFieldLength(Field: Integer): Byte;
begin
  Result := FFields[Field].FieldLength;
end;

Function TDBFFile.GetDecimalCount(Field: Integer): Byte;
begin
  Result := FFields[Field].DecimalCount;
end;

Function TDBFFile.GetFieldValues(Field: Integer): variant;
begin
  Result := FFields[Field].FieldValue;
end;

Function TDBFFile.GetPairs(Field: Integer): TPair<String,Variant>;
begin
  Result.Key := FFields[Field].FFieldName;
  Result.Value := FFields[Field].FieldValue;
end;

Function TDBFFile.IndexOf(const FieldName: String; const MustExist: Boolean = false): Integer;
begin
  Result := -1;
  for var Field := 0 to FFieldCount-1 do
  if SameText(FFields[Field].FFieldName,FieldName) then Exit(Field);
  if MustExist then raise Exception.Create('Field ' + FieldName + ' not found in ' + FFileName);
end;

Function TDBFFile.GetFields: TArray<TDBFField>;
begin
  Result := Copy(FFields);
end;

Function TDBFFile.GetFields(const FieldNames: array of String): TArray<TDBFField>;
begin
  SetLength(Result,Length(FieldNames));
  for var Field := low(Result) to high(Result) do
  Result[Field] := FFields[IndexOf(FieldNames[Field],true)];
end;

Function TDBFFile.GetValues: TArray<Variant>;
begin
  SetLength(Result,FFieldCount);
  for var Field := 0 to FFieldCount-1 do Result[Field] := FFields[Field].FieldValue;
end;

Function TDBFFile.GetPairs: TArray<TPair<String,Variant>>;
begin
  SetLength(Result,FFieldCount);
  for var Field := 0 to FFieldCount-1 do Result[Field] := GetPairs(Field);
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TDBFReader.Create(const FileName: String);
begin
  inherited Create;
  FRecordIndex := -1;
  FFileName := FileName;
  FileStream := TBufferedFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite,4096);
  FileReader := TBinaryReader.Create(FileStream,TEncoding.ANSI);
  // Read table file header
  Version := FileReader.ReadByte and 7;
  if Version = 4 then raise Exception.Create('dBase level 7 files not supported');
  for var Skip := 1 to 3 do FileReader.ReadByte; // Last update date
  FRecordCount := FileReader.ReadInteger;
  FFieldCount := (FileReader.ReadInt16 div 32)-1;
  for var Skip := 1 to 2 do FileReader.ReadByte; // Nr record bytes
  for var Skip := 1 to 2 do FileReader.ReadByte; // Reserved
  FileReader.ReadByte; // Incomplete dBase IV transaction
  FileReader.ReadByte; // dBase IV encryption flag
  for var Skip := 1 to 12 do FileReader.ReadByte; // Reserved
  FileReader.ReadByte; // Production MDX flag
  FileReader.ReadByte; // Language driver
  for var Skip := 1 to 2 do FileReader.ReadByte; // Reserved
  // Read field descriptor records
  SetLength(FFields,FFieldCount);
  for var Field := 0 to FFieldCount-1 do
  begin
    for var NameChar := 1 to 11 do
    begin
      var Chr := FileReader.ReadChar;
      if Chr <> #0 then FFields[Field].FFieldName := FFields[Field].FFieldName + Chr;
    end;
    FFields[Field].FFieldType := FileReader.ReadChar;
    for var Skip := 1 to 4 do FileReader.ReadByte; // Reserved
    FFields[Field].FFieldLength := FileReader.ReadByte;
    FFields[Field].FDecimalCount := FileReader.ReadByte;
    for var Skip := 1 to 14 do FileReader.ReadByte;
  end;
  // Read header terminator
  FileReader.ReadByte;
end;

Function TDBFReader.NextRecord: Boolean;
Var
  DeletedRecord: Boolean;
begin
  if FRecordIndex < FRecordCount-1 then
  begin
    Result := true;
    Inc(FRecordIndex);
    repeat
      DeletedRecord := (FileReader.ReadChar = '*');
      for var Field := 0 to FFieldCount-1 do
      try
        case FFields[Field].FFieldType of
          'I': FFields[Field].FieldValue := FileReader.ReadInt32;
          'O': FFields[Field].FieldValue := FileReader.ReadDouble;
          else
            begin
              var FieldValue := '';
              var Asterisks := true;
              var Nullify := true;
              for var FieldChar := 1 to FFields[Field].FFieldLength do
              begin
                var Chr := FileReader.ReadChar;
                FieldValue := FieldValue + Chr;
                Asterisks := Asterisks and (Chr = '*');
                Nullify := Nullify and (Chr = #0);
              end;
              if Asterisks then
                if FFields[Field].FFieldType = 'C' then
                  FFields[Field].FieldValue := FieldValue
                else
                  FFields[Field].FieldValue := Null
              else
                if Nullify then
                  FFields[Field].FieldValue := Null
                else
                  case FFields[Field].FFieldType of
                    'C': FFields[Field].FieldValue := Trim(FieldValue);
                    'D': begin
                           var Year := Copy(FieldValue,1,4).ToInteger;
                           var Month := Copy(FieldValue,5,2).ToInteger;
                           var Day := Copy(FieldValue,7,2).ToInteger;
                           FFields[Field].FieldValue := EncodeDate(Year,Month,Day);
                         end;
                    'L': if (FieldValue='T') or (FieldValue='t') or (FieldValue='Y') or (FieldValue='y') then
                         begin
                           FFields[Field].FieldValue := true;
                         end else
                         if (FieldValue='F') or (FieldValue='f') or (FieldValue='N') or (FieldValue='n') then
                         begin
                           FFields[Field].FieldValue := false;
                         end else
                         if FieldValue = '?' then
                            FFields[Field].FieldValue := Null
                         else
                           raise Exception.Create('Invalid field value (' + FFields[Field].FFieldName +')');
                    'F','N':
                         begin
                           FieldValue := Trim(FieldValue);
                           if FieldValue = '' then
                             FFields[Field].FieldValue := Null
                           else
                             if FFields[Field].FDecimalCount = 0 then
                               FFields[Field].FieldValue := StrToInt(FieldValue)
                             else
                               FFields[Field].FieldValue := StrToFloat(FieldValue,FormatSettings);
                         end;
                    else
                      FFields[Field].FieldValue := Null;
                  end;
            end;
        end;
      except
        raise Exception.Create('Error reading dbf-field ' + FFields[Field].FieldName);
      end;
    until not DeletedRecord;
  end else Result := false;
end;

Function TDBFReader.NextRecord(var Values: array of Variant): Boolean;
begin
  if Length(Values) = FFieldCount then
    if NextRecord then
    begin
      Result := true;
      for var Field := 0 to FFieldCount-1 do Values[Field] := GetFieldValues(Field);
    end else
      Result := false
  else
    raise Exception.Create('Invalid number of fields');
end;

Destructor TDBFReader.Destroy;
begin
  FileReader.Free;
  FileStream.Free;
  inherited Destroy;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TDBFWriter.Create(const FileName: String; const Fields: array of TDBFField);
Var
  B: Byte;
  HeaderSize,RecordSize: Word;
  Year,Month,Day: Word;
begin
  inherited Create;
  FFieldCount := Length(Fields);
  FFields := TArrayBuilder<TDBFField>.Create(Fields);
  // Validate fields
  RecordSize := 1; // Deletion marker
  for var Field := low(FFields) to high(FFields) do
  if IndexOf(Fields[Field].FFieldName) = Field then
  begin
    Fields[Field].Validate;
    Inc(RecordSize,Fields[Field].FFieldLength);
  end else
    raise Exception.Create('Duplicate Field ' + Fields[field].FFieldName);
  // Open File
  FileStream := TBufferedFileStream.Create(FileName,fmCreate or fmShareDenyWrite,4096);
  FileWriter := TBinaryWriter.Create(FileStream,TEncoding.ANSI);
  // Write table file header
  FileWriter.Write(#3); // Version
  DecodeDate(Now,Year,Month,Day);
  B := Year-1900; // Year
  FileWriter.Write(B);
  B := Month; // Month
  FileWriter.Write(B);
  B := Day; // Day
  FileWriter.Write(B);
  FileWriter.Write(RecordCount);
  HeaderSize := (FFieldCount+1)*32 + 1;
  FileWriter.Write(HeaderSize);
  FileWriter.Write(RecordSize);
  for var Skip := 1 to 20 do FileWriter.Write(#0);
  // Write field descriptor records
  for var Field := 0 to FFieldCount-1 do
  begin
    var Name := FFields[Field].FFieldName;
    while Length(Name) < 11 do Name := Name + #0;
    FileWriter.Write(Name.ToCharArray);
    FileWriter.Write(FFields[Field].FFieldType);
    for var Skip := 1 to 4 do FileWriter.Write(#0); // Reserved
    FileWriter.Write(FFields[Field].FFieldLength);
    FileWriter.Write(FFields[Field].FDecimalCount);
    for var Skip := 1 to 14 do FileWriter.Write(#0); // Reserved
  end;
  // Write header terminator
  FileWriter.Write(#13);
end;

Constructor TDBFWriter.Create(const FileName: String; const DBFFile: TDBFFile);
begin
  Create(FileName,DBFFile.FFields);
end;

Procedure TDBFWriter.SetFieldValues(Field: Integer; Value: Variant);
begin
  FFields[Field].FieldValue := Value;
end;

Procedure TDBFWriter.AppendRecord;
Var
  Year,Month,Day: Word;
begin
  FileWriter.Write(' '); // Undeleted record
  for var Field := 0 to FFieldCount-1 do
  begin
    if VarIsNull(FFields[Field].FieldValue) then
      for var Chr := 1 to FFields[Field].FieldLength do FileWriter.Write(#0)
    else
      try
        case FFields[Field].FFieldType of
          'C': begin
                 var Value: String := FFields[Field].FieldValue;
                 if Value.Length > FFields[Field].FieldLength then
                   if FFields[Field].FTruncate then
                     Value := Copy(Value,1,FFields[Field].FieldLength)
                   else
                     raise Exception.Create('Field value exceeds field length')
                 else
                   while Length(Value) < FFields[Field].FieldLength do Value := Value + #0;
                 FileWriter.Write(Value.ToCharArray);
               end;
          'D': begin
                 var Value: TDateTime := FFields[Field].FieldValue;
                 DecodeDate(Value,Year,Month,Day);
                 FileWriter.Write(IntToStr(Year).ToCharArray);
                 if Month < 10 then
                   FileWriter.Write(('0'+IntToStr(Month)).ToCharArray)
                 else
                   FileWriter.Write(IntToStr(Month).ToCharArray);
                 if Day < 10 then
                   FileWriter.Write(('0'+IntToStr(Day)).ToCharArray)
                 else
                   FileWriter.Write(IntToStr(Day).ToCharArray);
               end;
          'L': begin
                 var Value: Boolean := FFields[Field].FieldValue;
                 if Value then FileWriter.Write('T') else FileWriter.Write('F');
               end;
          'F','N':
               begin
                 var Value: Float64 := FFields[Field].FieldValue;
                 var Text := FormatFloat(FFields[Field].FieldFormat,Value,FormatSettings);
                 if Text.Length > FFields[Field].FieldLength then
                   // Only truncate decimals
                   if FFields[Field].FTruncate and (FFields[Field].FDecimalCount > 0) then
                     if Text.Length-FFields[Field].FDecimalCount-1 <= FFields[Field].FieldLength then
                     begin
                       Text := Copy(Text,1,FFields[Field].FieldLength);
                       if Text[Text.Length] = '.' then
                       Text := ' ' + Copy(Text,1,FFields[Field].FieldLength-1);
                     end else
                       raise Exception.Create('Field value exceeds field length')
                   else
                     raise Exception.Create('Field value exceeds field length')
                 else
                   while Length(Text) < FFields[Field].FieldLength do Text := ' ' + Text;
                 FileWriter.Write(Text.ToCharArray);
               end;
          'I': begin
                 var Value: Integer := FFields[Field].FieldValue;
                 FileWriter.Write(Value);
               end;
          'O': begin
                 var Value: Float64 := FFields[Field].FieldValue;
                 FileWriter.Write(Value);
               end;
          else raise Exception.Create('Unsupported field type');
        end;
      except
        on E: Exception do raise Exception.Create(E.Message + ' (field=' +
                                                  FFields[Field].FFieldName + '; value=' +
                                                  VarToStr(FFields[Field].FieldValue) + ')');
      end;
    FFields[Field].FieldValue := Null;
  end;
  Inc(FRecordCount);
end;

Procedure TDBFWriter.AppendRecord(const Values: array of Variant);
begin
  if Length(Values) = FFieldCount then
  begin
    for var Field := 0 to FFieldCount-1 do SetFieldValues(Field,Values[Field]);
    AppendRecord;
  end else
    raise Exception.Create('Invalid number of fields');
end;

Destructor TDBFWriter.Destroy;
begin
  // Write eof marker
  var EOF: Byte := 26;
  if FileWriter <> nil then FileWriter.Write(EOF);
  // Update record count
  if FileStream <> nil then
  begin
    FileStream.FlushBuffer;
    FileStream.Position := 4;
    FileWriter.Write(RecordCount);
  end;
  // Close file
  FileWriter.Free;
  FileStream.Free;
  inherited Destroy;
end;

end.
