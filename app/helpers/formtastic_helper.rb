module FormtasticHelper
  def testhelper form, method
    render :partial => 'formtastic/string_input', 
           :layout => 'formtastic/input_wrapper', 
           :locals => {:form => form, :method => method}
  end
end
