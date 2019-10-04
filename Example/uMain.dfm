object Form1: TForm1
  Left = 402
  Top = 193
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'ASLR Checker'
  ClientHeight = 105
  ClientWidth = 337
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object Edit1: TEdit
    Left = 8
    Top = 72
    Width = 273
    Height = 21
    TabOrder = 0
  end
  object Button1: TButton
    Left = 287
    Top = 72
    Width = 41
    Height = 23
    Caption = '...'
    TabOrder = 1
    OnClick = Button1Click
  end
  object RadioGroup1: TRadioGroup
    Left = 8
    Top = 8
    Width = 321
    Height = 57
    Caption = 'Function:'
    Columns = 4
    ItemIndex = 0
    Items.Strings = (
      'func1'
      'func2'
      'func3'
      'func4')
    TabOrder = 2
  end
  object OpenDialog1: TOpenDialog
    Filter = 'Executable File (*.exe)|*.exe'
    Left = 104
    Top = 72
  end
end
