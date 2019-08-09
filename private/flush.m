function str = flush(self)
  % FLUSH read the return values from device
  if ~isvalid(self.serial), disp('flush: Invalid serial port'); return; end
  com = self.serial;
  str = '';
  while com.BytesAvailable
    str = [ str fscanf(com) ];
  end
end % flush
