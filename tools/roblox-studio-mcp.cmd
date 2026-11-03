@echo off
rem Stable launcher for the MCP proxy built into Roblox Studio (StudioMCP.exe, signed by Roblox Corporation).
rem Studio installs each update in a new %LOCALAPPDATA%\Roblox\Versions\version-* folder, so this picks the
rem newest one. Studio must be open with "Enable Studio as MCP server" on (Assistant settings) to answer.
setlocal
set "MCP_EXE="
for /f "delims=" %%D in ('dir /b /ad /o-d "%LOCALAPPDATA%\Roblox\Versions" 2^>nul') do (
  if not defined MCP_EXE if exist "%LOCALAPPDATA%\Roblox\Versions\%%D\StudioMCP.exe" set "MCP_EXE=%LOCALAPPDATA%\Roblox\Versions\%%D\StudioMCP.exe"
)
if not defined MCP_EXE (
  echo StudioMCP.exe not found: install Roblox Studio first 1>&2
  exit /b 3
)
"%MCP_EXE%" --stdio %*
