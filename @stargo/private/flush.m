function str = flush(self)
  % FLUSH read the return values from device
  if ~isvalid(self.private.serial), disp('flush: Invalid serial port'); return; end
  com = self.private.serial;
  str = '';
  while com.BytesAvailable
    str = [ str fscanf(com) ];
  end
end % flush
