function out = strcmp(self, in)
  % STRCMP identify commands within available ones.
  %   STRCMP(self, CMD) searches for CMD in available commands. CMD can be
  %   given as a single serial command. The return value is a structure.
  %
  %   STRCMP(self, { 'CMD1' 'CMD2' ... }) does the same with an array as input.
  if isstruct(in) && isfield(in,'send'), out = in; return;
  elseif isnumeric(in), out = self.commands(in); return;
  elseif ~ischar(in) && ~iscellstr(in)
    error([ '[' datestr(now) '] ERROR: ' mfilename '.strcmp: invalid input type ' class(in) ]);
  end
  in = cellstr(in);
  out = [];
  for index = 1:numel(in)
    this_in = in{index};
    if this_in(1) == ':', list = { self.commands.send };
    else                  list = { self.commands.name }; end
    tok = find(strcmpi(list, this_in));
    if numel(tok) == 1
      out = [ out self.commands(tok) ];
    else
      disp([ '[' datestr(now) '] WARNING: ' mfilename '.strcmp: can not find command ' this_in ' in list of available ones.' ]);
      out1.name = 'custom command';
      out1.send = this_in;
      out1.recv = '';
      out1.comment = '';
      out = [ out out1 ];
    end
  end
  
end % strcmp
