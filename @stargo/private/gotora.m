function c = gotora(self, ra)
  [h1,m1,s1] = convert2hms(ra,'hours'); c = '';
  if ~isempty(h1)
    c = write(self, 'set_ra',  h1,m1,round(s1));
    self.target_ra = [h1 m1 s1];
    pause(0.25); % make sure commands are received
    % now we request execution of move: get_slew ":MS#"
    write(self, 'get_slew');
  elseif isempty(self.target_ra), self.target_ra=self.state.get_ra;
  end
end % gotora
