" *** Public interface ***

let RubyDebugger = { 'commands': {}, 'variables': {}, 'settings': {}, 'breakpoints': [] }

function! RubyDebugger.start() dict
  let g:RubyDebugger.server = s:Server.new(s:rdebug_port, s:debugger_port, s:runtime_dir, s:tmp_file)
  call g:RubyDebugger.server.start()

  " Send only first breakpoint to the debugger. All other breakpoints will be
  " sent by 'set_breakpoint' command
  let breakpoint = get(g:RubyDebugger.breakpoints, 0)
  if type(breakpoint) == type({})
    call breakpoint.send_to_debugger()
  endif
  echo "Debugger started"
endfunction



function! RubyDebugger.receive_command() dict
  let cmd = join(readfile(s:tmp_file), "")
  call g:RubyDebugger.logger.put("Received command: " . cmd)
  " Clear command line
  if !empty(cmd)
    if match(cmd, '<breakpoint ') != -1
      call g:RubyDebugger.commands.jump_to_breakpoint(cmd)
    elseif match(cmd, '<suspended ') != -1
      call g:RubyDebugger.commands.jump_to_breakpoint(cmd)
    elseif match(cmd, '<breakpointAdded ') != -1
      call g:RubyDebugger.commands.set_breakpoint(cmd)
    elseif match(cmd, '<variables>') != -1
      call g:RubyDebugger.commands.set_variables(cmd)
    elseif match(cmd, '<error>') != -1
      call g:RubyDebugger.commands.error(cmd)
    elseif match(cmd, '<message>') != -1
      call g:RubyDebugger.commands.message(cmd)
    endif
  endif
endfunction


let RubyDebugger.send_command = function("s:send_message_to_debugger")


function! RubyDebugger.open_variables() dict
  if g:RubyDebugger.variables == {}
    echo "You are not in the running program"
  else
    call s:variables_window.toggle()
    call g:RubyDebugger.logger.put("Opened variables window")
  endif
endfunction


function! RubyDebugger.open_breakpoints() dict
  call s:breakpoints_window.toggle()
  call g:RubyDebugger.logger.put("Opened breakpoints window")
endfunction


function! RubyDebugger.toggle_breakpoint() dict
  let line = line(".")
  let file = s:get_filename()
  let existed_breakpoints = filter(copy(g:RubyDebugger.breakpoints), 'v:val.line == ' . line . ' && v:val.file == "' . file . '"')
  if empty(existed_breakpoints)
    let breakpoint = s:Breakpoint.new(file, line)
    call add(g:RubyDebugger.breakpoints, breakpoint)
    call breakpoint.send_to_debugger() 
  else
    let breakpoint = existed_breakpoints[0]
    call filter(g:RubyDebugger.breakpoints, 'v:val.id != ' . breakpoint.id)
    call breakpoint.delete()
  endif
endfunction


function! RubyDebugger.next() dict
  call g:RubyDebugger.send_command("next")
  call g:RubyDebugger.logger.put("Step over")
endfunction


function! RubyDebugger.step() dict
  call g:RubyDebugger.send_command("step")
  call g:RubyDebugger.logger.put("Step into")
endfunction


function! RubyDebugger.continue() dict
  call g:RubyDebugger.send_command("cont")
  call g:RubyDebugger.logger.put("Continue")
endfunction


function! RubyDebugger.exit() dict
  call g:RubyDebugger.send_command("exit")
endfunction

" *** End of public interface



