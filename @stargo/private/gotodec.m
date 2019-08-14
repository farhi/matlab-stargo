function c = gotodec(self, dec)
  [h2,m2,s2] = convert2hms(dec,'deg'); c = '';
  if ~isempty(h2)
    c = write(self, 'set_dec', h2,m2,round(s2));
    self.target_dec = [h2 m2 s2];
    pause(0.25); % make sure commands are received
  elseif isempty(self.target_dec), self.target_dec=self.state.get_dec;
  end
end % gotodec
