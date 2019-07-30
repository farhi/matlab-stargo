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
  end
