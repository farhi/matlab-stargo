function h = update_interface(self)

  % check if window is already opened
  h = [ findall(0, 'Tag','StarGo_window') findall(0, 'Tag','StarGo_GUI') ];
  self.private.figure = h;
  if ~isempty(h)
    set(0,'CurrentFigure', h); % make it active
    
    % transfer data
    set(h, 'Name', char(self));
    
    obj = findobj(h, 'Tag','stargo_status');
    % set color depending on STATE
    switch upper(self.status)
    case {'HOME','PARKED','STOPPED'}
      c = 'r';
    case {'MOVING','SLEWING','PARKING'}
      c = 'g';
    case {'TRACKING'}
      c = 'b';
    otherwise
      c = 'k';
    end
    set(obj, 'String', self.status,'ForegroundColor',c);
    
    obj = findobj(h, 'Tag','stargo_ra');
    set(obj, 'String', self.ra, ...
      'Tooltip',[ 'Right ascension. ' num2str(self.private.ra_deg,3) ' [deg]' ]);
    
    obj = findobj(h, 'Tag','stargo_dec');
    set(obj, 'String', self.dec, ...
      'Tooltip',[ 'Declinaison. ' num2str(self.private.dec_deg,3) ' [deg]' ]);
    
    obj = findobj(h, 'Tag','stargo_ra_moving');
    set(obj, 'Value', self.private.ra_move >= 1);
    
    obj = findobj(h, 'Tag','stargo_dec_moving');
    set(obj, 'Value', self.private.dec_move >= 1);
    
    obj = findobj(h, 'Tag','stargo_zoom');
    if 1 <= self.private.zoom && self.private.zoom <= 4
      set(obj, 'Value', round(self.private.zoom));
    end
    
    obj = findobj(h, 'Tag','stargo_target');
    set(obj, 'String', [ 'Target: ' self.target_name ]);
    if ~isempty(self.target_ra)
      set(obj, 'TooltipString',[ 'RA=' mat2str(round(self.target_ra)) ' DEC=' mat2str(round(self.target_dec)) ]);
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
  % store current axes
  a = [ findall(0, 'Tag','stargo_skychart') findall(0,'Tag','SkyChart_Axes') ];
  self.private.axes = a;
    
