package main
import win32 "core:sys/windows"
import "core:strings"
import "core:os"
import "core:path/filepath"

// foreign import msdia140 "system:diaguids.lib"

SymTagEnum :: enum u32 {
    SymTagNull,
    SymTagExe,
    SymTagCompiland,
    SymTagCompilandDetails,
    SymTagCompilandEnv,
    SymTagFunction,
    SymTagBlock,
    SymTagData,
    SymTagAnnotation,
    SymTagLabel,
    SymTagPublicSymbol,
    SymTagUDT,
    SymTagEnum,
    SymTagFunctionType,
    SymTagPointerType,
    SymTagArrayType,
    SymTagBaseType,
    SymTagTypedef,
    SymTagBaseClass,
    SymTagFriend,
    SymTagFunctionArgType,
    SymTagFuncDebugStart,
    SymTagFuncDebugEnd,
    SymTagUsingNamespace,
    SymTagVTableShape,
    SymTagVTable,
    SymTagCustom,
    SymTagThunk,
    SymTagCustomType,
    SymTagManagedType,
    SymTagDimension,
    SymTagCallSite,
    SymTagInlineSite,
    SymTagBaseInterface,
    SymTagVectorType,
    SymTagMatrixType,
    SymTagHLSLType,
    SymTagCaller,
    SymTagCallee,
    SymTagExport,
    SymTagHeapAllocationSite,
    SymTagCoffGroup,
    SymTagInlinee,
    SymTagTaggedUnionCase, // a case of a tagged union UDT type
    SymTagMax
}

NameSearchOptions :: enum u32 {
    nsNone	= 0,
    nsfCaseSensitive	= 0x1,
    nsfCaseInsensitive	= 0x2,
    nsfFNameExt	= 0x4,
    nsfRegularExpression	= 0x8,
    nsfUndecoratedName	= 0x10,
    nsCaseSensitive	= nsfCaseSensitive,
    nsCaseInsensitive	= nsfCaseInsensitive,
    nsFNameExt	= ( nsfCaseInsensitive | nsfFNameExt ) ,
    nsRegularExpression	= ( nsfRegularExpression | nsfCaseSensitive ) ,
    nsCaseInRegularExpression	= ( nsfRegularExpression | nsfCaseInsensitive ) 
}

IDiaLineNumber_UUID_STRING :: "B388EB14-BE4D-421d-A8A1-6CF7AB057086"
IDiaLineNumber_UUID := &win32.IID{0xB388EB14, 0xBE4D, 0x421d, {0xA8, 0xA1, 0x6C, 0xF7, 0xAB, 0x05, 0x70, 0x86}}
IDiaLineNumber :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idialinenumber_vtable: ^IDiaLineNumber_VTable,
}

IDiaLineNumber_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,

    get_compiland: proc "system" (this: ^IDiaLineNumber, pRetVal: ^^IDiaSymbol) -> win32.HRESULT,
    get_sourceFile: proc "system" (this: ^IDiaLineNumber, pRetVal: ^^IDiaSourceFile) -> win32.HRESULT,
    get_lineNumber: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_lineNumberEnd: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_columnNumber: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_columnNumberEnd: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_addressSection: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_addressOffset: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_relativeVirtualAddress: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_virtualAddress: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.ULONGLONG) -> win32.HRESULT,
    get_length: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_sourceFileId: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_statement: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.BOOL) -> win32.HRESULT,
    get_compilandId: proc "system" (this: ^IDiaLineNumber, pRetVal: ^win32.DWORD) -> win32.HRESULT,
}

IDiaEnumLineNumbers_UUID_STRING :: "FE30E878-54AC-44f1-81BA-39DE940F6052"
IDiaEnumLineNumbers_UUID := &win32.IID{0xFE30E878, 0x54AC, 0x44f1, {0x81, 0xBA, 0x39, 0xDE, 0x94, 0x0F, 0x60, 0x52}}
IDiaEnumLineNumbers :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiaenumlinenumbers_vtable: ^IDiaEnumLineNumbers_VTable,
}

IDiaEnumLineNumbers_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,

    get__NewEnum: proc "system" (this: ^IDiaEnumLineNumbers, pRetVal: ^^win32.IUnknown) -> win32.HRESULT,
    get_Count: proc "system" (this: ^IDiaEnumLineNumbers, pRetVal: ^win32.LONG) -> win32.HRESULT,
    Item: proc "system" (this: ^IDiaEnumLineNumbers, index: win32.DWORD, lineNumber: ^^IDiaLineNumber) -> win32.HRESULT,
    Next: proc "system" (this: ^IDiaEnumLineNumbers, celt: win32.ULONG, rgelt: ^^IDiaLineNumber, pceltFetched: ^win32.ULONG) -> win32.HRESULT,
    Skip: proc "system" (this: ^IDiaEnumLineNumbers, celt: win32.ULONG) -> win32.HRESULT,
    Reset: proc "system" (this: ^IDiaEnumLineNumbers) -> win32.HRESULT,
    Clone: proc "system" (this: ^IDiaEnumLineNumbers, ppenum: ^^IDiaEnumLineNumbers) -> win32.HRESULT,
}

IDiaEnumSourceFiles_UUID_STRING :: "10F3DBD9-664F-4469-B808-9471C7A50538"
IDiaEnumSourceFiles_UUID := &win32.IID{0x10F3DBD9, 0x664F, 0x4469, {0xB8, 0x08, 0x94, 0x71, 0xC7, 0xA5, 0x05, 0x38}}
IDiaEnumSourceFiles :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiaenumsourcefiles_vtable: ^IDiaEnumSourceFiles_VTable,
}

IDiaEnumSourceFiles_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,

    get__NewEnum: proc "system" (this: ^IDiaEnumSourceFiles, pRetVal: ^^win32.IUnknown) -> win32.HRESULT,
    get_Count: proc "system" (this: ^IDiaEnumSourceFiles, pRetVal: ^win32.LONG) -> win32.HRESULT,
    Item: proc "system" (this: ^IDiaEnumSourceFiles, index: win32.DWORD, lineNumber: ^^IDiaSourceFile) -> win32.HRESULT,
    Next: proc "system" (this: ^IDiaEnumSourceFiles, celt: win32.ULONG, rgelt: ^^IDiaSourceFile, pceltFetched: ^win32.ULONG) -> win32.HRESULT,
    Skip: proc "system" (this: ^IDiaEnumSourceFiles, celt: win32.ULONG) -> win32.HRESULT,
    Reset: proc "system" (this: ^IDiaEnumSourceFiles) -> win32.HRESULT,
    Clone: proc "system" (this: ^IDiaEnumSourceFiles, ppenum: ^^IDiaEnumSourceFiles) -> win32.HRESULT,
}

IDiaSourceFile_UUID_STRING :: "A2EF5353-F5A8-4eb3-90D2-CB526ACB3CDD"
IDiaSourceFile_UUID := &win32.IID{0xA2EF5353, 0xF5A8, 0x4eb3, {0x90, 0xD2, 0xCB, 0x52, 0x6A, 0xCB, 0x3C, 0xDD}}
IDiaSourceFile :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiasourcefile_vtable: ^IDiaSourceFile_VTable,
}

IDiaSourceFile_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,

    get_uniqueId: proc "system" (this: ^IDiaSourceFile, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_fileName: proc "system" (this: ^IDiaSourceFile, pRetVal: ^win32.BSTR) -> win32.HRESULT,
    get_checksumType: proc "system" (this: ^IDiaSourceFile, pRetVal: ^win32.DWORD) -> win32.HRESULT,
    get_compilands: proc "system" (this: ^IDiaSourceFile, pRetVal: ^^IDiaEnumSymbols) -> win32.HRESULT,
    get_checksum: proc "system" (this: ^IDiaSourceFile, cbData: win32.DWORD, pcbData: ^win32.DWORD, pbData: ^win32.BYTE) -> win32.HRESULT,
}

IDiaEnumSymbolsByAddr_UUID_STRING :: "624B7D9C-24EA-4421-9D06-3B577471C1FA"
IDiaEnumSymbolsByAddr_UUID := &win32.IID{0x624B7D9C, 0x24EA, 0x4421, {0x9D, 0x06, 0x3B, 0x57, 0x74, 0x71, 0xC1, 0xFA}}
IDiaEnumSymbolsByAddr :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiaenumsymbolsbyaddr_vtable: ^IDiaEnumSymbolsByAddr_VTable,
}

IDiaEnumSymbolsByAddr_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,
}

IDiaEnumTables_UUID_STRING :: "C65C2B0A-1150-4d7a-AFCC-E05BF3DEE81E"
IDiaEnumTables_UUID := &win32.IID{0xC65C2B0A, 0x1150, 0x4d7a, {0xAF, 0xCC, 0xE0, 0x5B, 0xF3, 0xDE, 0xE8, 0x1E}}
IDiaEnumTables :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiaenumtables_vtable: ^IDiaEnumTables_VTable,
}

IDiaEnumTables_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,
}

IDiaEnumSymbols_UUID_STRING :: "CAB72C48-443B-48f5-9B0B-42F0820AB29A"
IDiaEnumSymbols_UUID := &win32.IID{0xCAB72C48, 0x443B, 0x48f5, {0x9b, 0x0b, 0x42, 0xf0, 0x82, 0x0a, 0xb2, 0x9a}}
IDiaEnumSymbols :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiaenumsymbols_vtable: ^IDiaEnumSymbols_VTable,
}

IDiaEnumSymbols_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,

    get__NewEnum: proc "system" (this: ^IDiaEnumSymbols, pRetVal: ^^win32.IUnknown) -> win32.HRESULT,
    get_Count: proc "system" (this: ^IDiaEnumSymbols, pRetVal: ^win32.LONG) -> win32.HRESULT,
    Item: proc "system" (this: ^IDiaEnumSymbols, index: win32.DWORD, symbol: ^^IDiaSymbol) -> win32.HRESULT,
    Next: proc "system" (this: ^IDiaEnumSymbols, celt: win32.ULONG, rgelt: ^^IDiaSymbol, pceltFetched: ^win32.ULONG) -> win32.HRESULT,
}

IDiaSymbol_UUID_STRING :: "cb787b2f-bd6c-4635-ba52-933126bd2dcd"
IDiaSymbol_UUID := &win32.IID{0xcb787b2f, 0xbd6c, 0x4635, {0xba, 0x52, 0x93, 0x31, 0x26, 0xbd, 0x2d, 0xcd}}
IDiaSymbol :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiasymbol_vtable: ^IDiaSymbol_VTable,
}

IDiaSymbol_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,

    get_symIndexId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_symTag: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_name: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BSTR) -> win32.HRESULT, 
    get_lexicalParent: proc "system" (this: ^IDiaSymbol, pRetVal: ^^IDiaSymbol) -> win32.HRESULT, 
    get_classParent: proc "system" (this: ^IDiaSymbol, pRetVal: ^^IDiaSymbol) -> win32.HRESULT, 
    get_type: proc "system" (this: ^IDiaSymbol, pRetVal: ^^IDiaSymbol) -> win32.HRESULT, 
    get_dataKind: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_locationType: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_addressSection: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_addressOffset: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_relativeVirtualAddress: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_virtualAddress: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.ULONGLONG) -> win32.HRESULT, 
    get_registerId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_offset: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.LONG) -> win32.HRESULT, 
    get_length: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.ULONGLONG) -> win32.HRESULT, 
    get_slot: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_volatileType: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_constType: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_unalignedType: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_access: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_libraryName: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BSTR) -> win32.HRESULT, 
    get_platform: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_editAndContinueEnabled: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_frontEndMajor: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_frontEndMinor: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_frontEndBuild: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_backEndMajor: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_backEndMinor: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_backEndBuild: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_sourceFileName: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BSTR) -> win32.HRESULT, 
    get_unused: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BSTR) -> win32.HRESULT, 
    get_thunkOrdinal: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_thisAdjust: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.LONG) -> win32.HRESULT, 
    get_virtualBaseOffset: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_virtual: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_intro: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_pure: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_callingConvention: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_value: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, /// it should be win32.VARIANT instead of win32.DWORD !!!!!!!
    get_baseType: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_token: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_timeStamp: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_guid: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.GUID) -> win32.HRESULT, 
    get_symbolsFileName: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BSTR) -> win32.HRESULT, 
    get_reference: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_count: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_bitPosition: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_arrayIndexType: proc "system" (this: ^IDiaSymbol, pRetVal: ^^IDiaSymbol) -> win32.HRESULT, 
    get_packed: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_constructor: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_overloadedOperator: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_nested: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_hasNestedTypes: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_hasAssignmentOperator: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_hasCastOperator: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_scoped: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_virtualBaseClass: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_indirectVirtualBaseClass: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_virtualBasePointerOffset: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.LONG) -> win32.HRESULT, 
    get_virtualTableShape: proc "system" (this: ^IDiaSymbol, pRetVal: ^^IDiaSymbol) -> win32.HRESULT, 
    get_lexicalParentId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_classParentId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_typeId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_arrayIndexTypeId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_virtualTableShapeId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_code: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_function: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_managed: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_msil: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_virtualBaseDispIndex: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_undecoratedName: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BSTR) -> win32.HRESULT, 
    get_age: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_signature: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_compilerGenerated: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_addressTaken: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.BOOL) -> win32.HRESULT, 
    get_rank: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_lowerBound: proc "system" (this: ^IDiaSymbol, pRetVal: ^^IDiaSymbol) -> win32.HRESULT, 
    get_upperBound: proc "system" (this: ^IDiaSymbol, pRetVal: ^^IDiaSymbol) -> win32.HRESULT, 
    get_lowerBoundId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_upperBoundId: proc "system" (this: ^IDiaSymbol, pRetVal: ^win32.DWORD) -> win32.HRESULT, 
    get_dataBytes: proc "system" (this: ^IDiaSymbol, cbData: win32.DWORD, pcbData: ^win32.DWORD, pbData: ^win32.BYTE) -> win32.HRESULT, 

    findChildren: proc "system" (this: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR,
        compareFlags: win32.DWORD, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,

    findChildrenEx: proc "system" (this: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR,
        compareFlags: win32.DWORD, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,

    findChildrenExByAddr: proc "system" (this: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR,
        compareFlags, isect, offset: win32.DWORD, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,

    findChildrenExByVA: proc "system" (this: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR,
        compareFlags: win32.DWORD, va: win32.ULONGLONG, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,

    findChildrenExByRVA: proc "system" (this: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR,
        compareFlags: win32.DWORD, rva: win32.ULONGLONG, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,
}

IDiaSession_UUID_STRING :: "2F609EE1-D1C8-4E24-8288-3326BADCD211"
IDiaSession_UUID := &win32.IID{0x2F609EE1, 0xD1C8, 0x4E24, {0x82, 0x88, 0x33, 0x26, 0xBA, 0xDC, 0xD2, 0x11}}
IDiaSession :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiasession_vtable: ^IDiaSession_VTable,
}

IDiaSession_VTable :: struct {
	using iunknown_vtable: win32.IUnknown_VTable,

    get_loadAddress: proc "system" (this: ^IDiaSession, pRetVal: ^win32.ULONGLONG) -> win32.HRESULT,
    
    put_loadAddress: proc "system" (this: ^IDiaSession, NewVal: win32.ULONGLONG) -> win32.HRESULT,

    get_globalScope: proc "system" (this: ^IDiaSession, pRetVal: ^^IDiaSymbol) -> win32.HRESULT,
    getEnumTables: proc "system" (this: ^IDiaSession, ppEnumTables: ^^IDiaEnumTables) -> win32.HRESULT,
    getSymbolsByAddr: proc "system" (this: ^IDiaSession, ppEnumbyAddr: ^^IDiaEnumSymbolsByAddr) -> win32.HRESULT,
    findChildren: proc "system" (this: ^IDiaSession, parent: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR, compareFlags: win32.DWORD, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,
    findChildrenEx: proc "system" (this: ^IDiaSession, parent: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR, compareFlags: win32.DWORD, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,
    findChildrenExByAddr: proc "system" (this: ^IDiaSession, parent: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR, compareFlags, isect, offset: win32.DWORD, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,
    findChildrenExByVA: proc "system" (this: ^IDiaSession, parent: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR, compareFlags: win32.DWORD, va: win32.ULONGLONG, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,
    findChildrenExByRVA: proc "system" (this: ^IDiaSession, parent: ^IDiaSymbol, symtag: SymTagEnum, name: win32.LPCOLESTR, compareFlags, rva: win32.DWORD, ppResult: ^^IDiaEnumSymbols) -> win32.HRESULT,
    findSymbolByAddr: proc "system" (this: ^IDiaSession, isect, offset: win32.DWORD, symtag: SymTagEnum, ppSymbol: ^^IDiaSymbol) -> win32.HRESULT,
    findSymbolByRVA: proc "system" (this: ^IDiaSession, rva: win32.DWORD, symtag: SymTagEnum, ppSymbol: ^^IDiaSymbol) -> win32.HRESULT,
    findSymbolByVA: proc "system" (this: ^IDiaSession, va: win32.ULONGLONG, symtag: SymTagEnum, ppSymbol: ^^IDiaSymbol) -> win32.HRESULT,
    findSymbolByToken: proc "system" (this: ^IDiaSession, token: win32.ULONG, symtag: SymTagEnum, ppSymbol: ^^IDiaSymbol) -> win32.HRESULT,
    symsAreEquiv: proc "system" (this: ^IDiaSession, symbolA, symbolB: ^IDiaSymbol) -> win32.HRESULT,
    symbolById: proc "system" (this: ^IDiaSession, id: win32.DWORD, ppSymbol: ^^IDiaSymbol) -> win32.HRESULT,
    findSymbolByRVAEx: proc "system" (this: ^IDiaSession, rva: win32.DWORD, symtag: SymTagEnum, ppSymbol: ^^IDiaSymbol, displacement: ^win32.c_long) -> win32.HRESULT,
    findSymbolByVAEx: proc "system" (this: ^IDiaSession, va: win32.ULONGLONG, symtag: SymTagEnum, ppSymbol: ^^IDiaSymbol, displacement: ^win32.c_long) -> win32.HRESULT,
    findFile: proc "system" (this: ^IDiaSession, pCompiland: ^IDiaSymbol, name: win32.LPCOLESTR, compareFlags: win32.DWORD, ppResult: ^^IDiaEnumSourceFiles) -> win32.HRESULT,
    findFileById: proc "system" (this: ^IDiaSession, uniqueId: win32.DWORD, ppResult: ^^IDiaSourceFile) -> win32.HRESULT,
    findLines: proc "system" (this: ^IDiaSession, compiland: ^IDiaSymbol, file: ^IDiaSourceFile, ppResult: ^^IDiaEnumLineNumbers) -> win32.HRESULT,
    findLinesByAddr: proc "system" (this: ^IDiaSession, seg, offset, length: win32.DWORD, ppResult: ^^IDiaEnumLineNumbers) -> win32.HRESULT,
    findLinesByRVA: proc "system" (this: ^IDiaSession, rva, length: win32.DWORD, ppResult: ^^IDiaEnumLineNumbers) -> win32.HRESULT,

}

DiaSource_UUID_STRING :: "e6756135-1e65-4d17-8576-610761398c3c"
DiaSource_UUID := &win32.IID{0xe6756135, 0x1e65, 0x4d17, {0x85, 0x76, 0x61, 0x07, 0x61, 0x39, 0x8c, 0x3c}}

IDiaDataSource_UUID_STRING :: "79F1BB5F-B66E-48e5-B6A9-1545C323CA3D"
IDiaDataSource_UUID := &win32.IID{0x79F1BB5F, 0xB66E, 0x48e5, {0xB6, 0xA9, 0x15, 0x45, 0xC3, 0x23, 0xCA, 0x3D}}
IDiaDataSource :: struct #raw_union {
	#subtype iunknown: win32.IUnknown,
	using idiadatasource_vtable: ^IDiaDataSource_VTable,
}

IDiaDataSource_VTable :: struct {
	using iunknown_vtable: win32.IUnknown_VTable,
    get_lastError: proc "system" (this: ^IDiaDataSource, pRetVal: ^win32.BSTR) -> win32.HRESULT,
	
    loadDataFromPdb: proc "system" (this: ^IDiaDataSource, pdbPath: win32.LPCOLESTR) -> win32.HRESULT,
	
    loadAndValidateDataFromPdb: proc "system" (this: ^IDiaDataSource, pdbPath: win32.LPCOLESTR, 
        pcsig70: ^win32.GUID, sig: win32.DWORD, age: win32.DWORD) -> win32.HRESULT,
    
    loadDataForExe: proc "system" (this: ^IDiaDataSource, executable, searchPath: win32.LPCOLESTR, pCallback: ^win32.IUnknown) -> win32.HRESULT,

    loadDataFromIStream: proc "system" (this: ^IDiaDataSource, pIStream: ^win32.IStream) -> win32.HRESULT,
    
    openSession: proc "system" (this: ^IDiaDataSource, ppSession: ^^IDiaSession) -> win32.HRESULT,

    loadDataFromCodeViewInfo: proc "system" (this: ^IDiaDataSource, executable, searchPath: win32.LPCOLESTR, 
        cbCvInfo: win32.DWORD, pbCvInfo: ^win32.BYTE, pCallback: ^win32.IUnknown) -> win32.HRESULT,

    loadDataFromMiscInfo: proc "system" (this: ^IDiaDataSource, executable, searchPath: win32.LPCOLESTR, 
        timeStampExe, timeStampDbg, sizeOfExe, cbMiscInfo: win32.DWORD, 
        pbMiscInfo: ^win32.BYTE, 
        pCallback: ^win32.IUnknown) -> win32.HRESULT,
}

PdbData :: struct {
    session: ^IDiaSession,
    globalSymbol: ^IDiaSymbol,

}

// Minimal IClassFactory binding so we can create the DIA data source straight from msdia140.dll
// without it being registered with regsvr32 (registration-free COM).
IClassFactory_UUID := &win32.IID{0x00000001, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
IClassFactory :: struct #raw_union {
    #subtype iunknown: win32.IUnknown,
    using iclassfactory_vtable: ^IClassFactory_VTable,
}
IClassFactory_VTable :: struct {
    using iunknown_vtable: win32.IUnknown_VTable,
    CreateInstance: proc "system" (this: ^IClassFactory, pUnkOuter: ^win32.IUnknown, riid: win32.REFIID, ppvObject: ^rawptr) -> win32.HRESULT,
    LockServer:     proc "system" (this: ^IClassFactory, fLock: win32.BOOL) -> win32.HRESULT,
}

DllGetClassObjectProc :: #type proc "system" (rclsid: win32.REFCLSID, riid: win32.REFIID, ppv: ^rawptr) -> win32.HRESULT

// Locates msdia140.dll inside a Visual Studio installation so we can load it at runtime instead
// of requiring it to be registered or copied next to the editor. Returns the full path.
findMsdiaDll :: proc() -> (string, bool) {
    diaSubPath :: "DIA SDK\\bin\\amd64\\msdia140.dll" // amd64 because the editor is a 64-bit process

    // 1. The VS developer environment variable, if the editor was launched from a dev prompt.
    if vsDir := os.get_env("VSINSTALLDIR", context.temp_allocator); vsDir != "" {
        candidate := fmt.tprintf("%s\\%s", strings.trim_suffix(vsDir, "\\"), diaSubPath)
        if os.exists(candidate) { return candidate, true }
    }

    roots := []string{
        "C:\\Program Files\\Microsoft Visual Studio",
        "C:\\Program Files (x86)\\Microsoft Visual Studio",
    }

    // 2. Standard install locations (cheap, exact os.exists checks).
    years := []string{ "2026", "2022", "2019", "2017" }
    editions := []string{ "Community", "Professional", "Enterprise", "Preview", "BuildTools" }
    for root in roots {
        for year in years {
            for edition in editions {
                candidate := fmt.tprintf("%s\\%s\\%s\\%s", root, year, edition, diaSubPath)
                if os.exists(candidate) { return candidate, true }
            }
        }
    }

    // 3. Catch-all for any other year/edition via globbing.
    for root in roots {
        pattern := fmt.tprintf("%s\\*\\*\\%s", root, diaSubPath)
        if matches, err := filepath.glob(pattern, context.temp_allocator); err == .None && len(matches) > 0 {
            return matches[0], true
        }
    }

    return "", false
}

// Creates an IDiaDataSource by loading msdia140.dll directly, so the editor works even when the
// dll hasn't been registered. Tries PATH/app dir first, then the Visual Studio installation.
createDiaDataSourceRegFree :: proc() -> (^IDiaDataSource, bool) {
    hModule := win32.LoadLibraryW(win32.utf8_to_wstring("msdia140.dll"))
    if hModule == nil {
        if dllPath, found := findMsdiaDll(); found {
            fmt.println("Loading DIA from:", dllPath)
            hModule = win32.LoadLibraryW(win32.utf8_to_wstring(dllPath))
        }
    }
    if hModule == nil { return nil, false }

    getClassObjectAddr := win32.GetProcAddress(hModule, "DllGetClassObject")
    if getClassObjectAddr == nil { return nil, false }
    dllGetClassObject := cast(DllGetClassObjectProc)getClassObjectAddr

    classFactory: ^IClassFactory
    hr := dllGetClassObject(DiaSource_UUID, IClassFactory_UUID, cast(^rawptr)(&classFactory))
    if hr != 0 || classFactory == nil { return nil, false }
    defer classFactory->Release()

    dataSource: ^IDiaDataSource
    hr = classFactory->CreateInstance(nil, IDiaDataSource_UUID, cast(^rawptr)(&dataSource))
    if hr != 0 { return nil, false }

    return dataSource, true
}

initPdbData :: proc(pdbFilePath: string) -> (PdbData, bool) {
    dataSource: ^IDiaDataSource
    win32.CoInitialize(nil)
    // NOTE: if it can't find dll it will return 14007 error, to fix it run regsvr32 <path_to_msdia140.dll>
    hr := win32.CoCreateInstance(DiaSource_UUID, nil, win32.CLSCTX_INPROC_SERVER, IDiaDataSource_UUID, cast(^win32.LPVOID)(&dataSource))
    if hr != 0 {
        // msdia140.dll isn't registered - fall back to loading it directly.
        regFreeSource, ok := createDiaDataSourceRegFree()
        if !ok {
            fmt.printfln("DIA: could not create data source (CoCreateInstance: %#X). Either run 'regsvr32 msdia140.dll' (elevated) or copy msdia140.dll next to the editor exe.", u32(hr))
            return {}, false
        }
        dataSource = regFreeSource
    }

    path := win32.utf8_to_wstring(pdbFilePath)
    hr = dataSource->loadDataFromPdb(transmute(win32.LPCOLESTR)(path))
    if hr != 0 {
        lastError: win32.BSTR
        dataSource->get_lastError(&lastError)
        errText, _ := win32.wstring_to_utf8(win32.wstring(lastError), -1)
        fmt.printfln("DIA: loadDataFromPdb('%s') failed: %#X (%s)", pdbFilePath, u32(hr), errText)
        dataSource->Release()
        return {}, false
    }

    dataSession: ^IDiaSession
    hr = dataSource->openSession(&dataSession)
    if hr != 0 {
        fmt.printfln("DIA: openSession failed: %#X", u32(hr))
        dataSource->Release()
        return {}, false
    }

    pGlobal: ^IDiaSymbol
    hr = dataSession->get_globalScope(&pGlobal)
    if hr != 0 {
        fmt.printfln("DIA: get_globalScope failed: %#X", u32(hr))
        dataSession->Release()
        dataSource->Release()
        return {}, false
    }

    return PdbData{
        session = dataSession,
        globalSymbol = pGlobal
    }, true
}

getFunctionNameByRVA :: proc(session: ^IDiaSession, rva: u32) -> (string, bool) {
    pSymbol: ^IDiaSymbol
    hr := session->findSymbolByRVA(rva, .SymTagFunction, &pSymbol)
    if hr != 0 {
        return "(source file not found)", false
    }
    // assert(hr == 0)
    defer pSymbol->Release()

    functionName: win32.BSTR
    hr = pSymbol->get_name(&functionName)
    assert(hr == 0)

    name, _ := win32.wstring_to_utf8(win32.wstring(functionName), -1)

    return name, true
}

getRVABySourcePosition :: proc(session: ^IDiaSession, filePath: string, line: i32) -> u32 {
    filePathWide := win32.utf8_to_wstring(filePath)

    pEnumSourceFiles: ^IDiaEnumSourceFiles
    hr := session->findFile(nil, transmute(win32.LPCOLESTR)filePathWide, u32(NameSearchOptions.nsCaseInsensitive), &pEnumSourceFiles)
    if hr != 0 { return 0 } // file is not part of this module's pdb
    defer pEnumSourceFiles->Release()

    foundFilesCount: i32
    hr = pEnumSourceFiles->get_Count(&foundFilesCount)
    if hr != 0 || foundFilesCount <= 0 { return 0 }
    
    lineRVA: u32
    celt: win32.ULONG
    pSourceFile: ^IDiaSourceFile
    fileFound := false

    for pEnumSourceFiles->Next(1, &pSourceFile, &celt) == 0 && celt == 1 {
        fileFound = true
        break
    }

    if !fileFound { return 0 }

    pEnumSymbols: ^IDiaEnumSymbols
    hr = pSourceFile->get_compilands(&pEnumSymbols)
    assert(hr == 0)

    compiland: ^IDiaSymbol
    got: win32.ULONG
    hr = pEnumSymbols->Next(1, &compiland, &got)
    assert(hr == 0)

    // compiland2: ^IDiaSymbol
    // hr = pEnumSymbols->Next(1, &compiland2, &got)

    // compilandName: win32.BSTR
    // hr = compiland->get_name(&compilandName)

    // fmt.println(win32.wstring_to_utf8(win32.wstring(compilandName), -1))

    pEnumLineNumbers: ^IDiaEnumLineNumbers
    hr = session->findLines(compiland, pSourceFile, &pEnumLineNumbers)
    test := win32.GetLastError()
    assert(hr == 0)
    defer pEnumLineNumbers->Release()

    pLine: ^IDiaLineNumber
    // lineFound := false
    for pEnumLineNumbers->Next(1, &pLine, &celt) == 0 && celt == 1 {
        defer pLine->Release()

        currentLine: u32
        hr = pLine->get_lineNumber(&currentLine)
        assert(hr == 0)

        if currentLine == u32(line) {
            hr = pLine->get_relativeVirtualAddress(&lineRVA)
            assert(hr == 0)

            return lineRVA
        }
    }

    return 0
}

getSourcePositionByRVA :: proc(session: ^IDiaSession, rva: u32) -> (string, u32, u32, u32) {
    pLines: ^IDiaEnumLineNumbers
    hr := session->findLinesByRVA(rva, 1, &pLines)
    // findLinesByRVA fails (leaving pLines nil) for any RVA not in this pdb, e.g. an address in a
    // system DLL while single-stepping. Guard it - dereferencing pLines below would crash.
    if hr != 0 || pLines == nil { return "", 0, 0, 0 }
    defer pLines->Release()

    pLine: ^IDiaLineNumber
    celt: win32.ULONG
    for pLines->Next(1, &pLine, &celt) == 0 && celt == 1 {
        defer pLine->Release()
        line: u32
        column: u32
        
        hr = pLine->get_lineNumber(&line)
        assert(hr == 0)
        hr = pLine->get_columnNumber(&column)
        assert(hr == 0)

        lineLength: u32
        pLine->get_length(&lineLength)
        assert(hr == 0)

        pSourceFile: ^IDiaSourceFile
        fileNameP: win32.BSTR

        hr = pLine->get_sourceFile(&pSourceFile)
        assert(hr == 0)
        defer pSourceFile->Release()

        hr = pSourceFile->get_fileName(&fileNameP)
        assert(hr == 0)

        fileName, err := win32.wstring_to_utf8(win32.wstring(fileNameP), -1)
        assert(err == nil)

        return fileName, line, column, lineLength
    }

    return "", 0, 0, 0
}

getFunctionsWithRVA :: proc(pdbData: PdbData) -> map[string]u32 {
    diaEnumSymbols: ^IDiaEnumSymbols
    hr := pdbData.globalSymbol->findChildrenEx(.SymTagFunction, nil, 0, &diaEnumSymbols) // TODO: findChildren returns 0x80070057, which is super weird!!!
    assert(hr == 0)

    pFunction: ^IDiaSymbol
    celt: win32.ULONG = 0

    functions := make(map[string]u32)
    for {        
        hr = diaEnumSymbols->Next(1, &pFunction, &celt)
        //assert(hr == 0)

        if hr != 0 || celt != 1 {
            break
        }
        bstrName: win32.BSTR
        hr = pFunction->get_name(&bstrName)
        assert(hr == 0)

        rva: win32.DWORD
        pFunction->get_relativeVirtualAddress(&rva)

        path2, _ := win32.wstring_to_utf8(win32.wstring(bstrName), -1)
        functions[path2] = rva
    }

    return functions
}

testDia :: proc() -> u32 {
    dataSource: ^IDiaDataSource
    win32.CoInitialize(nil)
    // NOTE: if it can't find dll it will return 14007 error, to fix it run regsvr32 <path_to_msdia140.dll>
    hr := win32.CoCreateInstance(DiaSource_UUID, nil, win32.CLSCTX_INPROC_SERVER, IDiaDataSource_UUID, cast(^win32.LPVOID)(&dataSource))

    path := win32.utf8_to_wstring("C:\\projects\\cpp_test_cmd\\x64\\Debug\\cpp_test_cmd.pdb")
    hr = dataSource->loadDataFromPdb(transmute(win32.LPCOLESTR)(path))
    // dataSource->Release();

    dataSession: ^IDiaSession
    hr = dataSource->openSession(&dataSession)

    pGlobal: ^IDiaSymbol
    hr = dataSession->get_globalScope(&pGlobal)
    
    // print all functions
    // tst32: win32.DWORD
    // hr = pGlobal->get_upperBoundId(&tst32)
    // test2 := win32.GetLastError()

    diaEnumSymbols: ^IDiaEnumSymbols
    hr = pGlobal->findChildrenEx(.SymTagFunction, nil, 0, &diaEnumSymbols) // TODO: findChildren returns 0x80070057, which is super weird!!!
    // test2 := win32.GetLastError()

    pFunction: ^IDiaSymbol
    celt: win32.ULONG = 0

    functions := make(map[string]u32)
    for {        
        hr = diaEnumSymbols->Next(1, &pFunction, &celt)

        if hr != 0 || celt != 1 {
            break
        }
        bstrName: win32.BSTR
        hr = pFunction->get_name(&bstrName)

        rva: win32.DWORD
        pFunction->get_relativeVirtualAddress(&rva)

        path2, _ := win32.wstring_to_utf8(win32.wstring(bstrName), -1)
        functions[path2] = rva
    }
    
    return functions["test"]
}