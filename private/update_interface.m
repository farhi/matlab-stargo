function h = update_interface(self)

  % check if window is already opened
  h = [ findall(0, 'Tag','StarGo_window') findall(0, 'Tag','StarGo_GUI') ];
  if ~isempty(h)
    set(0,'CurrentFigure', h); % make it active
    
    % transfer data
    set(h, 'Name', char(self));
    
    obj = findobj(h, 'Tag','stargo_status');
    set(obj, 'String', self.status);
    
    obj = findobj(h, 'Tag','stargo_ra');
    set(obj, 'String', self.ra);
    
    obj = findobj(h, 'Tag','stargo_dec');
    set(obj, 'String', self.dec);
    
    obj = findobj(h, 'Tag','stargo_ra_moving');
    set(obj, 'Value', self.state.ra_move >= 1);
    
    obj = findobj(h, 'Tag','stargo_dec_moving');
    set(obj, 'Value', self.state.dec_move >= 1);
    
    obj = findobj(h, 'Tag','stargo_zoom');
    if 1 <= self.state.zoom && self.state.zoom <= 4
      set(obj, 'Value', round(self.state.zoom));
    end
    
    % change button labels according to mount type
    % get_alignment(1): A-AzEl mounted, P-Equatorially mounted, G-german mounted equatorial
    if isfield(self.state, 'get_alignment') && iscell(self.state.get_alignment) ...
      && ischar(self.state.get_alignment{1})
      tags = {'stargo_s','stargo_n','stargo_e','stargo_w','stargo_ra_moving','stargo_dec_moving' };
      A    = {'S',       'N',       'E',       'W',       'EW',              'NS'};
      P    = {'DEC-',    'DEC+',    'RA+',     'RA-',     'RA',              'DEC'};
      for index=1:numel(tags)
        obj = findobj(h, 'Tag', tags{index});
        if isscalar(obj)
          if self.state.get_alignment{1} == 'A'
            set(obj, 'String', A{index}); 
          else
            set(obj, 'String', P{index}); 
          end
        end
      end
    end
  end
