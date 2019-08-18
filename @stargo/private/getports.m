function available = getports
  % GETPORTS find available serial ports.
  %   Returns a cell array of ports, or empty.
  
  % we use the error code returned by Matlab
  ME = [];
  try
    s = serial('IMPOSSIBLE_PORT'); fopen(s);
  catch ME
    % nop
    delete(s);
  end
  
  l0 = getReport(ME);
  token = 'Available ports';
  available = findstr(l0, token);
  if ~isempty(available)
    % remove token
    l1 = textscan(l0(available(1)+numel(token)+1:end),'%s','Delimiter','\n\r');
    l2 = strtrim(l1{1});
    % now we cut the result into pieces
    l3 = l2{1}; l3(end) = []; % remove last '.' char
    l4 = textscan(l3, '%s','Delimiter',' ');
    available = strtrim(l4{1});
  end
  
  if isempty(available) 
    available = {}; 
  end
end % getports
