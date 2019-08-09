function [p,self] = parseparams(self)
  % PARSEPARAMS interpret output and decode it.
  recv = self.bufferRecv; p=[];
  if isempty(recv), return; end
  % cut output from serial port into separate tokens
  recv = textscan(recv,'%s','Delimiter','# ','MultipleDelimsAsOne',true);
  recv = recv{1};
  if isempty(recv), return; end
  
  % check if we have a Z1 status string in received buffer
  toremove = [];
  allSent = self.bufferSent; 
  % we search for a pattern in sent that matches the actual recieved string
  for indexR=1:numel(recv)
    if isempty(recv{indexR}), continue; end
    for indexS=1:numel(allSent)
      sent = allSent(indexS); tok = [];
      if any(indexS == toremove), continue; end
      if isempty(sent.recv), continue; end
      try
        % look for an expected output 'sent' in the actual output 'recv'
        [tok,pos] = textscan(recv{indexR}, sent.recv);
      catch ME
        continue; % pattern does not match received string. try an other one.
      end

      if ~isempty(tok) && ~any(cellfun(@isempty,tok))
        if numel(tok) == 1
          tok = tok{1};
        end
        if iscell(tok) && all(cellfun(@isnumeric, tok))
          tok = cell2mat(tok);
        elseif iscell(tok) && all(cellfun(@ischar, tok))
          tok = char(tok);
        end
        self.state.(sent.name) = tok; % store in object 'state'
        p.(sent.name)   = tok;
        toremove(end+1) = indexS; % clear this request for search
        recv{indexR}    = [];     % clear this received output as it was found
        break; % go to next received item
      end % if tok
    end % for indexS
  end % for indexR
  toremove(toremove >  numel(self.bufferSent)) = [];
  toremove(toremove <= 0) = [];
  self.bufferSent(toremove) = [];
  if ~all(cellfun(@isempty, recv))
    self.bufferRecv = sprintf('%s#', recv{:});
  else
    self.bufferRecv = '';
  end
  self.state=orderfields(self.state);

end % parseparams
