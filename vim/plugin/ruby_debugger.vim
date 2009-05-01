map <Leader>b  :call g:RubyDebugger.toggle_breakpoint()<CR>
map <Leader>v  :call g:RubyDebugger.open_variables()<CR>
map <Leader>m  :call g:RubyDebugger.open_breakpoints()<CR>
map <Leader>s  :call g:RubyDebugger.step()<CR>
map <Leader>n  :call g:RubyDebugger.next()<CR>
map <Leader>c  :call g:RubyDebugger.continue()<CR>
map <Leader>e  :call g:RubyDebugger.exit()<CR>

command! Rdebugger :call g:RubyDebugger.start() 

" if exists("g:loaded_ruby_debugger")
"     finish
" endif
" if v:version < 700
"     echoerr "RubyDebugger: This plugin requires Vim >= 7."
"     finish
" endif
" let g:loaded_ruby_debugger = 1

let s:rdebug_port = 39767
let s:debugger_port = 39768
let s:runtime_dir = split(&runtimepath, ',')[0]
let s:tmp_file = s:runtime_dir . '/tmp/ruby_debugger'

if &t_Co < '16'
  let s:breakpoint_ctermbg = 1
else
  let s:breakpoint_ctermbg = 4
endif

" Init breakpoing signs
exe "hi Breakpoint term=NONE ctermbg=" . s:breakpoint_ctermbg . " guifg=#E6E1DC guibg=#7E1111"
sign define breakpoint linehl=Breakpoint  text=xx

" Init current line signs
hi CurrentLine term=NONE ctermbg=2 guifg=#E6E1DC guibg=#144212 term=NONE
sign define current_line linehl=CurrentLine text=>>

function! s:get_tags(cmd)
  let tags = []
  let cmd = a:cmd
  let inner_tags_match = s:get_inner_tags(cmd)
  if !empty(inner_tags_match)
    let pattern = '<.\{-}\/>' 
    let inner_tags = inner_tags_match[1]
    let tagmatch = matchlist(inner_tags, pattern)
    while empty(tagmatch) == 0
      call add(tags, tagmatch[0])
      let tagmatch[0] = escape(tagmatch[0], '[]')
      let inner_tags = substitute(inner_tags, tagmatch[0], '', '')
      let tagmatch = matchlist(inner_tags, pattern)
    endwhile
  endif
  return tags
endfunction


function! s:get_inner_tags(cmd)
  return matchlist(a:cmd, '^<.\{-}>\(.\{-}\)<\/.\{-}>$')
endfunction 


function! s:get_tag_attributes(cmd)
  let attributes = {}
  let cmd = a:cmd
  let pattern = "\\(\\w\\+\\)=[\"']\\(.\\{-}\\)[\"']"
  let attrmatch = matchlist(cmd, pattern) 
  while empty(attrmatch) == 0
    let attributes[attrmatch[1]] = attrmatch[2]
    let attrmatch[0] = escape(attrmatch[0], '[]')
    let cmd = substitute(cmd, attrmatch[0], '', '')
    let attrmatch = matchlist(cmd, pattern) 
  endwhile
  return attributes
endfunction


function! s:get_filename()
  return expand("%:p")
endfunction


function! s:send_message_to_debugger(message)
  call system("ruby -e \"require 'socket'; a = TCPSocket.open('localhost', 39768); a.puts('" . a:message . "'); a.close\"")
endfunction


function! s:jump_to_file(file, line)
  " If no buffer with this file has been loaded, create new one
  if !bufexists(bufname(a:file))
     exe ":e! " . a:file
  endif

  let window_number = bufwinnr(bufnr(a:file))
  if window_number != -1
     exe window_number . "wincmd w"
  endif

  " open buffer of a:file
  if bufname(a:file) != bufname("%")
     exe ":buffer " . bufnr(a:file)
  endif

  " jump to line
  exe ":" . a:line
  normal z.
  if foldlevel(a:line) != 0
     normal zo
  endif

  return bufname(a:file)

endfunction




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




" *** RubyDebugger Commands *** 


" <breakpoint file="test.rb" line="1" threadId="1" />
" <suspended file='test.rb' line='1' threadId='1' />
function! RubyDebugger.commands.jump_to_breakpoint(cmd) dict
  let attrs = s:get_tag_attributes(a:cmd) 
  call s:jump_to_file(attrs.file, attrs.line)
  call g:RubyDebugger.logger.put("Jumped to breakpoint " . attrs.file . ":" . attrs.line)


  if has("signs")
    exe ":sign unplace 120"
    exe ":sign place 120 line=" . attrs.line . " name=current_line file=" . attrs.file
  endif

  call g:RubyDebugger.send_command('var local')
endfunction


" <breakpointAdded no="1" location="test.rb:2" />
function! RubyDebugger.commands.set_breakpoint(cmd)
  let attrs = s:get_tag_attributes(a:cmd)
  let file_match = matchlist(attrs.location, '\(.*\):\(.*\)')
  " Set pid of current debugger to current breakpoint
  let pid = g:RubyDebugger.server.rdebug_pid

  for breakpoint in g:RubyDebugger.breakpoints
    if expand(breakpoint.file) == expand(file_match[1]) && expand(breakpoint.line) == expand(file_match[2])
      let breakpoint.debugger_id = attrs.no
      let breakpoint.rdebug_pid = pid
    endif
  endfor

  call g:RubyDebugger.logger.put("Breakpoint is set: " . file_match[1] . ":" . file_match[2])

  let not_assigned_breakpoints = filter(copy(g:RubyDebugger.breakpoints), '!has_key(v:val, "rdebug_pid") || v:val["rdebug_pid"] != ' . pid)
  let not_assigned_breakpoint = get(not_assigned_breakpoints, 0)
  if type(not_assigned_breakpoint) == type({})
    call not_assigned_breakpoint.send_to_debugger()
  endif
endfunction


" <variables>
"   <variable name="array" kind="local" value="Array (2 element(s))" type="Array" hasChildren="true" objectId="-0x2418a904"/>
" </variables>
function! RubyDebugger.commands.set_variables(cmd)
  let tags = s:get_tags(a:cmd)
  let list_of_variables = []
  for tag in tags
    let attrs = s:get_tag_attributes(tag)
    let variable = s:Var.new(attrs)
    call add(list_of_variables, variable)
  endfor
  if g:RubyDebugger.variables == {}
    let g:RubyDebugger.variables = s:VarParent.new({'hasChildren': 'true'})
    let g:RubyDebugger.variables.is_open = 1
    let g:RubyDebugger.variables.children = []
  endif
  if has_key(g:RubyDebugger, 'current_variable')
    let variable_name = g:RubyDebugger.current_variable
    call g:RubyDebugger.logger.put("Trying to find variable: " . variable_name)
    let variable = g:RubyDebugger.variables.find_variable({'name': variable_name})
    unlet g:RubyDebugger.current_variable
    if variable != {}
      call g:RubyDebugger.logger.put("Found variable: " . variable_name)
      call variable.add_childs(list_of_variables)
      let s:variables_window.data = g:RubyDebugger.variables
      call g:RubyDebugger.logger.put("Opening child variable: " . variable_name)
      call s:variables_window.open()
    else
      call g:RubyDebugger.logger.put("Can't found variable with name: " . variable_name)
    endif
  else
    if g:RubyDebugger.variables.children == []
      call g:RubyDebugger.variables.add_childs(list_of_variables)
      let s:variables_window.data = g:RubyDebugger.variables
      call g:RubyDebugger.logger.put("Initializing local variables")
    endif
  endif
endfunction


" <error>Error</error>
function! RubyDebugger.commands.error(cmd)
  let error_match = s:get_inner_tags(a:cmd) 
  if !empty(error_match)
    let error = error_match[1]
    echo "RubyDebugger Error: " . error
    call g:RubyDebugger.logger.put("Got error: " . error)
  endif
endfunction


" <message>Message</message>
function! RubyDebugger.commands.message(cmd)
  let message_match = s:get_inner_tags(a:cmd) 
  if !empty(message_match)
    let message = message_match[1]
    echo "RubyDebugger Message: " . message
    call g:RubyDebugger.logger.put("Got message: " . message)
  endif
endfunction

" *** End of debugger Commands ***




" *** Abstract Class for creating window. Should be inherited. ***

let s:Window = {} 
let s:Window['next_buffer_number'] = 1 
let s:Window['position'] = 'botright'
let s:Window['size'] = 10


function! s:Window.new(name, title, data) dict
  let new_variable = copy(self)
  let new_variable.name = a:name
  let new_variable.title = a:title
  let new_variable.data = a:data
  return new_variable
endfunction


function! s:Window.clear() dict
  silent 1,$delete _
endfunction


function! s:Window.close() dict
  if !self.is_open()
    throw "RubyDebug: Window " . self.name . " is not open"
  endif

  if winnr("$") != 1
    call self.focus()
    close
    exe "wincmd p"
  else
    :q
  endif
  call self._log("Closed window with name: " . self.name)
endfunction


function! s:Window.get_number() dict
  if self._exist_for_tab()
    return bufwinnr(self._buf_name())
  else
    return -1
  endif
endfunction


function! s:Window.display()
  call self._log("Start displaying data in window with name: " . self.name)
  call self.focus()
  setlocal modifiable

  let current_line = line(".")
  let current_column = col(".")
  let top_line = line("w0")

  call self.clear()

  call setline(top_line, self.title)
  call cursor(top_line + 1, current_column)

  call self._insert_data()
  call self._restore_view(top_line, current_line, current_column)

  setlocal nomodifiable
  call self._log("Complete displaying data in window with name: " . self.name)
endfunction


function! s:Window.focus() dict
  exe self.get_number() . " wincmd w"
  call self._log("Set focus to window with name: " . self.name)
endfunction


function! s:Window.is_open() dict
    return self.get_number() != -1
endfunction


function! s:Window.open() dict
    if !self.is_open()
      " create the window
      silent exec self.position . ' ' . self.size . ' new'

      if !self._exist_for_tab()
        call self._set_buf_name(self._next_buffer_name())
        silent! exec "edit " . self._buf_name()
        " This function does not exist in Window class and should be declared in
        " childrens
        call self.bind_mappings()
      else
        silent! exec "buffer " . self._buf_name()
      endif

      " set buffer options
      setlocal winfixwidth
      setlocal noswapfile
      setlocal buftype=nofile
      setlocal nowrap
      setlocal foldcolumn=0
      setlocal nobuflisted
      setlocal nospell
      iabc <buffer>
      setlocal cursorline
      setfiletype ruby_debugger_window
      call self._log("Opened window with name: " . self.name)
    endif
    call self.display()
endfunction


function! s:Window.toggle() dict
  call self._log("Toggling window with name: " . self.name)
  if self._exist_for_tab() && self.is_open()
    call self.close()
  else
    call self.open()
  end
endfunction


function! s:Window._buf_name() dict
  return t:window_{self.name}_buf_name
endfunction


function! s:Window._exist_for_tab() dict
  return exists("t:window_" . self.name . "_buf_name") 
endfunction


function! s:Window._insert_data() dict
  let old_p = @p
  let @p = self.render()
  silent put p
  let @p = old_p
  call self._log("Inserted data to window with name: " . self.name)
endfunction


function! s:Window._log(string) dict
  if has_key(self, 'logger')
    call self.logger.put(a:string)
  endif
endfunction


function! s:Window._next_buffer_name() dict
  let name = self.name . s:Window.next_buffer_number
  let s:Window.next_buffer_number += 1
  return name
endfunction


function! s:Window._restore_view(top_line, current_line, current_column) dict
 "restore the view
  let old_scrolloff=&scrolloff
  let &scrolloff=0
  call cursor(a:top_line, 1)
  normal! zt
  call cursor(a:current_line, a:current_column)
  let &scrolloff = old_scrolloff 
  call self._log("Restored view of window with name: " . self.name)
endfunction


function! s:Window._set_buf_name(name) dict
  let t:window_{self.name}_buf_name = a:name
endfunction









" Inherits variables window from abstract window class
let s:WindowVariables = copy(s:Window)

function! s:WindowVariables.bind_mappings()
  nnoremap <buffer> <2-leftmouse> :call <SID>window_variables_activate_node()<cr>
  nnoremap <buffer> o :call <SID>window_variables_activate_node()<cr>"
endfunction


function! s:WindowVariables.render() dict
  return self.data.render()
endfunction


" TODO: Is there some way to call s:WindowVariables.activate_node from mapping
" command?
function! s:window_variables_activate_node()
  let variable = s:Var.get_selected()
  if variable != {} && variable.type == "VarParent"
    if variable.is_open
      call variable.close()
    else
      call variable.open()
    endif
  endif
endfunction




let s:WindowBreakpoints = copy(s:Window)

function! s:WindowBreakpoints.bind_mappings()
  nnoremap <buffer> <2-leftmouse> :call <SID>window_breakpoints_activate_node()<cr>
  nnoremap <buffer> o :call <SID>window_breakpoints_activate_node()<cr>
  nnoremap <buffer> d :call <SID>window_breakpoints_delete_node()<cr>
endfunction


function! s:WindowBreakpoints.render() dict

endfunction


" TODO: Is there some way to call s:WindowBreakpoints.activate_node from mapping
" command?
function! s:window_breakpoints_activate_node()

endfunction


function! s:window_breakpoints_delete_node()

endfunction




let s:Var = {}

" This is a proxy method for creating new variable
function! s:Var.new(attrs)
  if has_key(a:attrs, 'hasChildren') && a:attrs['hasChildren'] == 'true'
    return s:VarParent.new(a:attrs)
  else
    return s:VarChild.new(a:attrs)
  end
endfunction


function! s:Var.get_selected()
  let line = getline(".") 
  let match = matchlist(line, '[| `]\+[+\-\~]\+\(.\{-}\)\s') 
  let name = get(match, 1)
  let variable = g:RubyDebugger.variables.find_variable({'name' : name})
  let g:RubyDebugger.current_variable = name
  return variable
endfunction


" *** Start of variables ***
let s:VarChild = {}


" Initializes new variable without childs
function! s:VarChild.new(attrs)
  let new_variable = copy(self)
  let new_variable.attributes = a:attrs
  let new_variable.parent = {}
  let new_variable.type = "VarChild"
  return new_variable
endfunction


" Renders data of the variable
function! s:VarChild.render()
  return self._render(0, 0, [], len(self.parent.children) ==# 1)
endfunction


function! s:VarChild._render(depth, draw_text, vertical_map, is_last_child)
  let output = ""
  if a:draw_text ==# 1
    let tree_parts = ''

    "get all the leading spaces and vertical tree parts for this line
    if a:depth > 1
      for j in a:vertical_map[0:-2]
        if j ==# 1
          let tree_parts = tree_parts . '| '
        else
          let tree_parts = tree_parts . '  '
        endif
      endfor
    endif
    
    "get the last vertical tree part for this line which will be different
    "if this node is the last child of its parent
    if a:is_last_child
      let tree_parts = tree_parts . '`'
    else
      let tree_parts = tree_parts . '|'
    endif

    "smack the appropriate dir/file symbol on the line before the file/dir
    "name itself
    if self.is_parent()
      if self.is_open
        let tree_parts = tree_parts . '~'
      else
        let tree_parts = tree_parts . '+'
      endif
    else
      let tree_parts = tree_parts . '-'
    endif
    let line = tree_parts . self.to_s()
    let output = output . line . "\n"

  endif

  if self.is_parent() && self.is_open

    if len(self.children) > 0

      "draw all the nodes children except the last
      let last_index = len(self.children) - 1
      if last_index > 0
        for i in self.children[0:last_index - 1]
          let output = output . i._render(a:depth + 1, 1, add(copy(a:vertical_map), 1), 0)
        endfor
      endif

      "draw the last child, indicating that it IS the last
      let output = output . self.children[last_index]._render(a:depth + 1, 1, add(copy(a:vertical_map), 0), 1)

    endif
  endif

  return output

endfunction


function! s:VarChild.open()
  return 0
endfunction


function! s:VarChild.close()
  return 0
endfunction


function! s:VarChild.is_parent()
  return has_key(self.attributes, 'hasChildren') && get(self.attributes, 'hasChildren') ==# 'true'
endfunction


function! s:VarChild.to_s()
  return get(self.attributes, "name", "undefined") . ' ' . get(self.attributes, "type", "undefined") . ' ' . get(self.attributes, "value", "undefined")
endfunction


function! s:VarChild.find_variable(attrs)
  if self._match_attributes(a:attrs)
    return self
  else
    return {}
  endif
endfunction


function! s:VarChild._match_attributes(attrs)
  let conditions = 1
  for attr in keys(a:attrs)
    let conditions = conditions && (has_key(self.attributes, attr) && self.attributes[attr] == a:attrs[attr]) 
  endfor
  
  return conditions
endfunction




" Inherits VarParent from VarChild
let s:VarParent = copy(s:VarChild)


" Renders data of the variable
function! s:VarParent.render()
  return self._render(0, 0, [], len(self.children) ==# 1)
endfunction



" Initializes new variable with childs
function! s:VarParent.new(attrs)
  if !has_key(a:attrs, 'hasChildren') || a:attrs['hasChildren'] != 'true'
    throw "RubyDebug: VarParent must be initialized with hasChildren = true"
  endif
  let new_variable = copy(self)
  let new_variable.attributes = a:attrs
  let new_variable.parent = {}
  let new_variable.is_open = 0
  let new_variable.children = []
  let new_variable.type = "VarParent"
  return new_variable
endfunction


function! s:VarParent.open()
  let self.is_open = 1
  call self._init_children()
  return 0
endfunction


function! s:VarParent.close()
  let self.is_open = 0
  call s:variables_window.display()
  if exists(g:RubyDebugger.current_variable)
    unlet g:RubyDebugger.current_variable
  endif
  return 0
endfunction



function! s:VarParent._init_children()
  "remove all the current child nodes
  let self.children = []
  if !has_key(self.attributes, "name")
    return 0
  endif

  let g:RubyDebugger.current_variable = self.attributes.name
  if has_key(self.attributes, 'objectId')
    call g:RubyDebugger.send_command('var instance ' . self.attributes.objectId)
  endif

endfunction


function! s:VarParent.add_childs(childs)
  if type(a:childs) == type([])
    for child in a:childs
      let child.parent = self
    endfor
    call extend(self.children, a:childs)
  else
    let a:childs.parent = self
    call add(self.children, a:childs)
  end
endfunction


function! s:VarParent.find_variable(attrs)
  if self._match_attributes(a:attrs)
    return self
  else
    for child in self.children
      let result = child.find_variable(a:attrs)
      if result != {}
        return result
      endif
    endfor
  endif
  return {}
endfunction


let s:Logger = {} 

function! s:Logger.new(file)
  let new_variable = copy(self)
  let new_variable.file = a:file
  call writefile([], new_variable.file)
  return new_variable
endfunction

function! s:Logger.put(string)
  let file = readfile(self.file)
  let string = strftime("%Y/%m/%d %H:%M:%S") . ' ' . a:string
  call add(file, string)
  call writefile(file, self.file)
endfunction




let s:Breakpoint = { 'id': 0 }

function! s:Breakpoint.new(file, line)
  let var = copy(self)
  let var.file = a:file
  let var.line = a:line
  let s:Breakpoint.id += 1
  let var.id = s:Breakpoint.id

  call var._set_sign()
  call var._log("Set breakpoint to: " . var.file . ":" . var.line)
  return var
endfunction


function! s:Breakpoint._set_sign() dict
  if has("signs")
    exe ":sign place " . self.id . " line=" . self.line . " name=breakpoint file=" . self.file
  endif
endfunction


function! s:Breakpoint._unset_sign() dict
  if has("signs")
    exe ":sign unplace " . self.id
  endif
endfunction


function! s:Breakpoint.delete() dict
  call self._unset_sign()
  call self._send_delete_to_debugger()
endfunction


function! s:Breakpoint.send_to_debugger() dict
  if has_key(g:RubyDebugger, 'server') && g:RubyDebugger.server.is_running()
    let message = 'break ' . self.file . ':' . self.line
    call g:RubyDebugger.send_command(message)
  endif
endfunction


function! s:Breakpoint._log(string) dict
  call g:RubyDebugger.logger.put(a:string)
endfunction


function! s:Breakpoint._send_delete_to_debugger() dict
  if has_key(g:RubyDebugger, 'server') && g:RubyDebugger.server.is_running()
    let message = 'delete ' . self.debugger_id
    call g:RubyDebugger.send_command(message)
  endif
endfunction



let s:Server = {}

function! s:Server.new(rdebug_port, debugger_port, runtime_dir, tmp_file) dict
  let var = copy(self)
  let var.rdebug_port = a:rdebug_port
  let var.debugger_port = a:debugger_port
  let var.runtime_dir = a:runtime_dir
  let var.tmp_file = a:tmp_file
  return var
endfunction


function! s:Server.start() dict
  call self._stop_server('localhost', s:rdebug_port)
  call self._stop_server('localhost', s:debugger_port)
  let rdebug = 'rdebug-ide -p ' . self.rdebug_port . ' -- script/server &'
  let debugger = 'ruby ' . expand(self.runtime_dir . "/bin/ruby_debugger.rb") . ' ' . self.rdebug_port . ' ' . self.debugger_port . ' ' . v:progname . ' ' . v:servername . ' "' . self.tmp_file . '" &'
  call system(rdebug)
  exe 'sleep 2'
  call system(debugger)

  let self.rdebug_pid = self._get_pid('localhost', self.rdebug_port)
  let self.debugger_pid = self._get_pid('localhost', self.debugger_port)

  call g:RubyDebugger.logger.put("Start debugger")
endfunction  


function! s:Server.stop() dict
  call self._kill_process(self.rdebug_pid)
  call self._kill_process(self.debugger_pid)
  let self.rdebug_pid = ""
  let self.debugger_pid = ""
endfunction


function! s:Server.is_running() dict
  return (self._get_pid('localhost', self.rdebug_port) =~ '^\d\+$') && (self._get_pid('localhost', self.debugger_port) =~ '^\d\+$')
endfunction


function! s:Server._get_pid(bind, port)
  if has("win32") || has("win64")
    let netstat = system("netstat -anop tcp")
    let pid = matchstr(netstat, '\<' . a:bind . ':' . a:port . '\>.\{-\}LISTENING\s\+\zs\d\+')
  elseif executable('lsof')
    let pid = system("lsof -i 4tcp@" . a:bind . ':' . a:port . " | grep LISTEN | awk '{print $2}'")
    let pid = substitute(pid, '\n', '', '')
  else
    let pid = ""
  endif
  return pid
endfunction


function! s:Server._stop_server(bind, port) dict
  let pid = self._get_pid(a:bind, a:port)
  if pid =~ '^\d\+$'
    call self._kill_process(pid)
  endif
endfunction


function! s:Server._kill_process(pid) dict
  echo "Killing server with pid " . a:pid
  call system("ruby -e 'Process.kill(9," . a:pid . ")'")
  sleep 100m
  call self._log("Killed server with pid: " . a:pid)
endfunction


function! s:Server._log(string) dict
  call g:RubyDebugger.logger.put(a:string)
endfunction





let s:variables_window = s:WindowVariables.new("variables", "Variables_Window", g:RubyDebugger.variables)
let s:breakpoints_window = s:WindowBreakpoints.new("breakpoints", "Breakpoints_Window", g:RubyDebugger.breakpoints)

let RubyDebugger.logger = s:Logger.new(s:runtime_dir . '/tmp/ruby_debugger_log')
let s:variables_window.logger = RubyDebugger.logger
let s:breakpoints_window.logger = RubyDebugger.logger

