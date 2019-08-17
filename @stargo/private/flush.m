function str = flush(self)
  % FLUSH read the return values from device
  
  str = '';
  if strncmp(self.dev, 'sim',3), return; end
  if ~isa(self.private.serial,'serial') || ~isvalid(self.private.serial) 
    disp([ mfilename ': Invalid serial port ' self.dev ]); return;
  end
  
  com = self.private.serial;
  while com.BytesAvailable
    str = [ str fscanf(com) ];
  end
end % flush
