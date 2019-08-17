function plot_telescope(self)
  % plot_telescope: plot a marker at the telescope location
  
  % FOV for focal length and camera sensor:
  % FOV=sensor size / focal length in radians -> one for H and V
  % https://www.dpreview.com/forums/post/54555442
  %
  % pointer could be a sqare symbol with actual mean dimension (enevr know in which orientation)
  
  % first remove any previous pointer
    delete(findobj(self.figure, 'Tag','SkyChart_Pointer1'));
    delete(findobj(self.figure, 'Tag','SkyChart_Pointer2'));
    delete(findobj(self.figure, 'Tag','SkyChart_Line'));
    
  % get the scope location
  RA = []; DEC=[];
  if isobject(self.telescope) && isvalid(self.telescope)
    try
      % get the current scope location
      RA =  self.telescope.private.ra_deg;
      DEC=  self.telescope.private.dec_deg;
    catch ME
      disp(getReport(ME))
    end
  end
  
  % plot
  if ~isempty(RA)
    % compute Alt-Az and stereographic polar coords
    [Az, Alt] = radec2altaz(RA, DEC, self.julianday, self.place);
    [X, Y]    = pr_stereographic_polar(Az+90, Alt);
    
    % the plot the pointer at scope location (cross + circle), 0.5 deg
    plot(X,Y, 'ro', 'MarkerSize', 20, 'Tag','SkyChart_Pointer1'); 
    plot(X,Y, 'r+', 'MarkerSize', 20, 'Tag','SkyChart_Pointer2');
    
    % we also draw a line when the target is defined, so that we can see where we go
    if ~isempty(self.telescope.target_name) && strcmp(self.telescope.status,'MOVING')
      target_ra_deg = hms2angle(self.telescope.target_ra)*15; % in deg
      target_dec_deg= hms2angle(self.telescope.target_dec); % in deg
      [tAz, tAlt] = radec2altaz(target_ra_deg, target_dec_deg, self.julianday, self.place);
      [tX, tY]    = pr_stereographic_polar(tAz+90, tAlt);
      line([ X tX ], [ Y tY ], 'LineStyle','--','Color','r','Tag','SkyChart_Line');
    end
  end
  

end % plot_telescope

function ang = hms2angle(h,m,s)
  % hms2angle convert hh:mm:ss to an angle in [deg]
  if nargin == 1 && numel(h) == 3
    m = h(2); s=h(3); h=h(1);
  end
  ang = double(h) + double(m)/60 + double(s)/3600;
end % hms2angle
