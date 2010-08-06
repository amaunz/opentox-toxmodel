helpers do

  def hide_link(destination)
    @link_id = 0 unless @link_id
    @link_id += 1
    haml :js_link, :locals => {:name => "hide", :destination => destination, :method => "hide"}, :layout => false
  end

  def toggle_link(destination,name)
    @link_id = 0 unless @link_id
    @link_id += 1
    haml :js_link, :locals => {:name => name, :destination => destination, :method => "toggle"}, :layout => false
  end

  def compound_image(compound,features)
    haml :compound_image, :locals => {:compound => compound, :features => features}, :layout => false
  end
  
  def activity_markup(activity)
    case activity.class.to_s
    when /Float/
      haml ".other #{sprintf('%.03g', activity)}", :layout => false
    else
      if activity #true
        haml ".active active", :layout => false
      elsif !activity # false
        haml ".inactive inactive", :layout => false
      else
        haml ".other #{activity.to_s}", :layout => false
      end
    end
  end

  def neighbors_navigation
    @page = 0 unless @page
    haml :neighbors_navigation, :layout => false
  end

end

