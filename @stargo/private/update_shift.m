function update_shift(self)
  % UPDATE_SHIFT handle shift operation
  %   start, test target values, change speed, test for done

  % determine current offset to target
  delta_ra = 0; delta_dec = 0;
  if ~isempty(self.private.shift_ra)
    delta_ra = self.private.shift_ra - self.private.ra_deg;
    if   delta_ra > 0, ra_dir = 'e';     % RA+
    else               ra_dir = 'w'; end % RA-
  end
  if ~isempty(self.private.shift_dec)
    delta_dec = self.private.shift_dec - self.private.dec_deg;
    if   delta_dec > 0,dec_dir = 'n';     % DEC+
    else               dec_dir = 's'; end % DEC-
  end
  
  % determine current zoom level and accurary
  current_zoom = self.private.zoom;
  ra_accuracy  = self.private.ra_speeds(current_zoom);
  dec_accuracy = self.private.dec_speeds(current_zoom);

  ra_sign_changed  = delta_ra *self.private.shift_delta_ra < 0;
  dec_sign_changed = delta_dec*self.private.shift_delta_dec < 0;
  if abs(delta_ra)  > abs(self.private.shift_delta_ra),  ra_sign_changed=true; end
  if abs(delta_dec) > abs(self.private.shift_delta_dec), dec_sign_changed=true; end

  % we stop motors when they are moving, close to target within twice accuracy/step
  % must also stop when target has been passed
  if self.private.ra_move > 1 && (abs(delta_ra) < 2*ra_accuracy || ra_sign_changed)
    move(self, [ ra_dir ' stop' ]);
  end
  if self.private.dec_move > 1 && (abs(delta_dec) < 2*dec_accuracy || dec_sign_changed)
    move(self, [ dec_dir ' stop' ]);
  end
  
  self.private.shift_delta_ra = delta_ra;
  self.private.shift_delta_dec= delta_dec;
  
  % we can only change zoom when both motors are idle
  if self.private.ra_move <= 1 && self.private.dec_move <= 1
    best_ra_zoom  = find(abs(delta_ra)  > self.private.ra_speeds,  1, 'last');
    best_dec_zoom = find(abs(delta_dec) > self.private.dec_speeds, 1, 'last');
    if isempty(best_ra_zoom),  best_ra_zoom  = find(self.private.dec_speeds>0,1,'first'); end
    if isempty(best_dec_zoom), best_dec_zoom = find(self.private.ra_speeds>0, 1,'first'); end
    best_zoom     = max(best_ra_zoom, best_dec_zoom);
    zoom(self, best_zoom);
  else best_zoom = []; end
  
  % end shift when both motors idle, are within target
  best_accuracy  = max([ self.private.ra_speeds(1) self.private.dec_speeds(1) ]);
  if ~isempty(best_zoom) ...
    && self.private.ra_move <= 1 && self.private.dec_move <= 1 ...
    && abs(delta_ra) < 2*best_accuracy && abs(delta_dec) < 2*best_accuracy
    self.private.shift_ra  = [];
    self.private.shift_dec = [];
    disp([ mfilename ' shift: target reached.' ]);
    return
  end
  
  % we can only start motors when they are idle, after a zoom change, and further
  % than twice zoom accuracy
  if ~isempty(best_zoom)
    ra_accuracy  = self.private.ra_speeds(best_zoom);
    dec_accuracy = self.private.dec_speeds(best_zoom);
    if self.private.ra_move <= 1 && abs(delta_ra) > ra_accuracy
      move(self, ra_dir);
    end
    if self.private.dec_move <= 1 && abs(delta_dec) > dec_accuracy
      move(self, dec_dir);
    end
  end
  
end % update_shift
