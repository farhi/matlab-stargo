function update_checks(self)
  for f={'pulsems','ra_move','dec_move','ra_deg','dec_deg', ...
    'ra_speed', 'dec_speed'}
    if ~isfield(self.private, f{1}) self.private.(f{1}) = 0; end
  end
  if ~isfield(self.private, 'zoom') sb.private.zoom        = 1; end % current zoom in 1:4
  if ~isfield(self.private, 'ra_speeds') sb.private.ra_speeds   = zeros(1,4); % current in deg/s
  if ~isfield(self.private, 'dec_speeds') sb.private.dec_speeds  = zeros(1,4); % current in deg/s
  if ~isfield(self.private, 'shift_ra') sb.private.shift_ra    = []; end
  if ~isfield(self.private, 'shift_dec') sb.private.shift_dec   = []; end
  if ~isfield(self.private, 'lastUpdate') sb.private.lastUpdate  = []; end
end % update_checks

