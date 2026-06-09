@echo off
REM Compiles every fixture (one per subfolder) to an .exe + .pdb with MSVC debug info.
REM Uses /Zi (codeview pdb), /Od (no optimization, so locals/stepping resolve), /MDd (debug CRT).
REM Absolute source paths are passed so the pdb records absolute paths, matching what the tests set.
REM Re-run this if you move the repo or edit a fixture: it rebakes the source paths in the pdbs.

setlocal
set VCVARS="C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist %VCVARS% (
    echo Could not find vcvars64.bat - edit the VCVARS path in this script.
    exit /b 1
)
call %VCVARS% >nul

cd /d "%~dp0"
for %%f in (arithmetic control_flow recursion structs pointers templates stl inheritance) do (
    echo Compiling %%f\%%f.cpp
    cl /nologo /Zi /Od /EHsc /MDd "%~dp0%%f\%%f.cpp" /Fe:"%~dp0%%f\%%f.exe" /Fo:"%~dp0%%f\%%f.obj" /Fd:"%~dp0%%f\%%f.pdb" || exit /b 1
    del /q "%~dp0%%f\%%f.obj" "%~dp0%%f\%%f.ilk" 2>nul
)
echo Done.
