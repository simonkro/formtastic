# Override the default ActiveRecordHelper behaviour of wrapping the input.
# This gets taken care of semantically by adding an error class to the LI tag
# containing the input.
ActionView::Base.field_error_proc = proc do |html_tag, instance_tag|
  html_tag
end

module Formtastic #:nodoc:

  class SemanticFormBuilder < ActionView::Helpers::FormBuilder

    @@all_fields_required_by_default = true
    @@label_str_method = :humanize
    @@collection_label_methods = %w[to_label display_name full_name name title username login value to_s]
    @@file_methods = [ :file?, :public_filename ]
    @@template_root = File.join(Rails.configuration.view_path, 'forms')

    cattr_accessor :all_fields_required_by_default, :label_str_method,
      :collection_label_methods, :file_methods, :template_root

    attr_accessor :template

    # Returns a suitable form input for the given +method+, using the database column information
    # and other factors (like the method name) to figure out what you probably want.
    #
    # Options:
    #
    # * :as - override the input type (eg force a :string to render as a :password field)
    # * :label - use something other than the method name as the label (or fieldset legend) text
    # * :required - specify if the column is required (true) or not (false)
    # * :hint - provide some text to hint or help the user provide the correct information for a field
    # * :input_html - provide options that will be passed down to the generated input
    # * :wrapper_html - provide options that will be passed down to the li wrapper
    #
    # Input Types:
    #
    # Most inputs map directly to one of ActiveRecord's column types by default (eg string_input),
    # but there are a few special cases and some simplification (:integer, :float and :decimal
    # columns all map to a single numeric_input, for example).
    #
    # * :select (a select menu for associations) - default to association names
    # * :time_zone (a select menu with time zones)
    # * :radio (a set of radio inputs for associations) - default to association names
    # * :password (a password input) - default for :string column types with 'password' in the method name
    # * :text (a textarea) - default for :text column types
    # * :date (a date select) - default for :date column types
    # * :datetime (a date and time select) - default for :datetime and :timestamp column types
    # * :time (a time select) - default for :time column types
    # * :boolean (a checkbox) - default for :boolean column types (you can also have booleans as :select and :radio)
    # * :string (a text field) - default for :string column types
    # * :numeric (a text field, like string) - default for :integer, :float and :decimal column types
    #
    # Example:
    #
    #   <% semantic_form_for @employee do |form| %>
    #     <% form.inputs do -%>
    #       <%= form.input :name, :label => "Full Name"%>
    #       <%= form.input :manager_id, :as => :radio %>
    #       <%= form.input :hired_at, :as => :date, :label => "Date Hired" %>
    #       <%= form.input :phone, :required => false, :hint => "Eg: +1 555 1234" %>
    #     <% end %>
    #   <% end %>
    #
    def input(method, options = {})
      reflection = find_reflection(method)

      locals = { #defaults
        :builder => self, :id => generate_html_id(method), :as => default_input_type(method),
        :checked_value => '1', :unchecked_value => '0', :msgs => errors_for(method, options),
        :required => method_required?(method), :collection => find_collection_for_column(method, options),
        :reflection => reflection, :input_name => generate_association_input_name(method),
        :multiple => reflection && [:has_many, :has_and_belongs_to_many].include?(reflection.macro),
        :humanized_attribute_name => humanized_attribute_name(method), :method => method,
        :object_name => @object.class.try(:human_name) || @object_name.to_s.send(@@label_str_method),
        :hint => nil, :priority_zones => nil, :input_html => {}, :label_html => {}, :wrapper_html => {},
        :input_options => {}
      }.merge(options)

      template.render :partial => find_template("#{locals[:as]}_input", "input"), :locals => locals
    end

    # Creates an input fieldset and ol tag wrapping for use around a set of inputs.  It can be
    # called either with a block (in which you can do the usual Rails form stuff, HTML, ERB, etc),
    # or with a list of fields.  These two examples are functionally equivalent:
    #
    #   # With a block:
    #   <% semantic_form_for @post do |form| %>
    #     <% form.inputs do %>
    #       <%= form.input :title %>
    #       <%= form.input :body %>
    #     <% end %>
    #   <% end %>
    #
    #   # With a list of fields:
    #   <% semantic_form_for @post do |form| %>
    #     <%= form.inputs :title, :body %>
    #   <% end %>
    #
    #   # Output:
    #   <form ...>
    #     <fieldset class="inputs">
    #       <ol>
    #         <li class="string">...</li>
    #         <li class="text">...</li>
    #       </ol>
    #     </fieldset>
    #   </form>
    #
    # === Quick Forms
    #
    # When called without a block or a field list, an input is rendered for each column in the
    # model's database table, just like Rails' scaffolding.  You'll obviously want more control
    # than this in a production application, but it's a great way to get started, then come back
    # later to customise the form with a field list or a block of inputs.  Example:
    #
    #   <% semantic_form_for @post do |form| %>
    #     <%= form.inputs %>
    #   <% end %>
    #
    # === Options
    #
    # All options (with the exception of :name) are passed down to the fieldset as HTML
    # attributes (id, class, style, etc).  If provided, the :name option is passed into a
    # legend tag inside the fieldset (otherwise a legend is not generated).
    #
    #   # With a block:
    #   <% semantic_form_for @post do |form| %>
    #     <% form.inputs :name => "Create a new post", :style => "border:1px;" do %>
    #       ...
    #     <% end %>
    #   <% end %>
    #
    #   # With a list (the options must come after the field list):
    #   <% semantic_form_for @post do |form| %>
    #     <%= form.inputs :title, :body, :name => "Create a new post", :style => "border:1px;" %>
    #   <% end %>
    #
    # === It's basically a fieldset!
    #
    # Instead of hard-coding fieldsets & legends into your form to logically group related fields,
    # use inputs:
    #
    #   <% semantic_form_for @post do |f| %>
    #     <% f.inputs do %>
    #       <%= f.input :title %>
    #       <%= f.input :body %>
    #     <% end %>
    #     <% f.inputs :name => "Advanced", :id => "advanced" do %>
    #       <%= f.input :created_at %>
    #       <%= f.input :user_id, :label => "Author" %>
    #     <% end %>
    #   <% end %>
    #
    #   # Output:
    #   <form ...>
    #     <fieldset class="inputs">
    #       <ol>
    #         <li class="string">...</li>
    #         <li class="text">...</li>
    #       </ol>
    #     </fieldset>
    #     <fieldset class="inputs" id="advanced">
    #       <legend><span>Advanced</span></legend>
    #       <ol>
    #         <li class="datetime">...</li>
    #         <li class="select">...</li>
    #       </ol>
    #     </fieldset>
    #   </form>
    #
    # === Nested attributes
    #
    # As in Rails, you can use semantic_fields_for to nest attributes:
    #
    #   <% semantic_form_for @post do |form| %>
    #     <%= form.inputs :title, :body %>
    #
    #     <% form.semantic_fields_for :author, @bob do |author_form| %>
    #       <% author_form.inputs do %>
    #         <%= author_form.input :first_name, :required => false %>
    #         <%= author_form.input :last_name %>
    #       <% end %>
    #     <% end %>
    #   <% end %>
    #
    # But this does not look formtastic! This is equivalent:
    #
    #   <% semantic_form_for @post do |form| %>
    #     <%= form.inputs :title, :body %>
    #     <% form.inputs :for => [ :author, @bob ] do |author_form| %>
    #       <%= author_form.input :first_name, :required => false %>
    #       <%= author_form.input :last_name %>
    #     <% end %>
    #   <% end %>
    #
    # And if you don't need to give options to your input call, you could do it
    # in just one line:
    #
    #   <% semantic_form_for @post do |form| %>
    #     <%= form.inputs :title, :body %>
    #     <%= form.inputs :first_name, :last_name, :for => @bob %>
    #   <% end %>
    #
    # Just remember that calling inputs generates a new fieldset to wrap your
    # inputs. If you have two separate models, but, semantically, on the page
    # they are part of the same fieldset, you should use semantic_fields_for
    # instead (just as you would do with Rails' form builder).
    #
    def inputs(*args, &block)
      html_options = args.extract_options!
      html_options[:class] ||= "inputs"

      if html_options[:for]
        inputs_for_nested_attributes(args, html_options, &block)
      elsif block_given?
        field_set_and_list_wrapping(:input, html_options, &block)
      else
        if @object && args.empty?
          args  = @object.class.reflections.map { |n,_| n if _.macro == :belongs_to }
          args += @object.class.content_columns.map(&:name)
          args -= %w[created_at updated_at created_on updated_on]
          args.compact!
        end
        contents = args.map { |method| input(method.to_sym) }

        field_set_and_list_wrapping(:input, html_options, contents)
      end
    end
    alias :input_field_set :inputs

    # Creates a fieldset and ol tag wrapping for form buttons / actions as list items.
    # See inputs documentation for a full example.  The fieldset's default class attriute
    # is set to "buttons".
    #
    # See inputs for html attributes and special options.
    def buttons(*args, &block)
      html_options = args.extract_options!
      html_options[:class] ||= "buttons"

      if block_given?
        field_set_and_list_wrapping(:button, html_options, &block)
      else
        args = [:commit] if args.empty?
        contents = args.map { |button_name| send(:"#{button_name}_button") }
        field_set_and_list_wrapping(:button, html_options, contents)
      end
    end
    alias :button_field_set :buttons

    # Creates a button tag using a template with the same name as the button or the generic
    # _button.html.erb / _button.html.haml if no special template is found
    def method_missing(symbol, *args, &block)
      if symbol.to_s =~ /^(.*)_button$/
        locals = {:object => @object, :builder => self, :button_name => $1}
        locals[:new_record]  = @object.try(:new_record?)
        locals[:object_name] = @object.class.try(:human_name) || @object_name.to_s.send(@@label_str_method)
        return template.render :partial => find_template("#{$1}_button", "button"), :locals => locals
      end
      super
    end

    # A thin wrapper around #fields_for to set :builder => Formtastic::SemanticFormBuilder
    # for nesting forms:
    #
    #   # Example:
    #   <% semantic_form_for @post do |post| %>
    #     <% post.semantic_fields_for :author do |author| %>
    #       <% author.inputs :name %>
    #     <% end %>
    #   <% end %>
    #
    #   # Output:
    #   <form ...>
    #     <fieldset class="inputs">
    #       <ol>
    #         <li class="string"><input type='text' name='post[author][name]' id='post_author_name' /></li>
    #       </ol>
    #     </fieldset>
    #   </form>
    #
    def semantic_fields_for(record_or_name_or_array, *args, &block)
      opts = args.extract_options!
      opts.merge!(:builder => Formtastic::SemanticFormBuilder)
      args.push(opts)
      fields_for(record_or_name_or_array, *args, &block)
    end

    protected

    # render(:partial => '...') doesn't want the full path of the template
    def self.template_root(full_path = false)
      full_path ? @@template_root : @@template_root.gsub(Rails.configuration.view_path + '/', '')
    end

    # checks to make sure the template exists
    def self.template_exists?(template)
      !Dir[File.join(template_root(true), "_#{template}.html.*")].blank?
    end

    # caches which template to use given a set of choices
    @@find_template_cache = Hash.new do |h, choices|
      choice = choices.find{|t| template_exists?(t)}
      h[choices] = File.join(template_root, choice || choices.first)
    end

    # returns the first template found
    def find_template(*choices)
      @@find_template_cache[choices]
    end

    # Deals with :for option when it's supplied to inputs methods. Additional
    # options to be passed down to :for should be supplied using :for_options
    # key.
    #
    # It should raise an error if a block with arity zero is given.
    #
    def inputs_for_nested_attributes(args, options, &block)
      args << options.merge!(:parent => { :builder => self, :for => options[:for] })

      fields_for_block = if block_given?
        raise ArgumentError, 'You gave :for option with a block to inputs method, ' <<
                             'but the block does not accept any argument.' if block.arity <= 0

        proc { |f| f.inputs(*args){ block.call(f) } }
      else
        proc { |f| f.inputs(*args) }
      end

      fields_for_args = [options.delete(:for), options.delete(:for_options) || {}].flatten
      semantic_fields_for(*fields_for_args, &fields_for_block)
    end

    # Determins if the attribute (eg :title) should be considered required or not.
    #
    # * if the :required option was provided in the options hash, the true/false value will be
    #   returned immediately, allowing the view to override any guesswork that follows:
    #
    # * if the :required option isn't provided in the options hash, and the ValidationReflection
    #   plugin is installed (http://github.com/redinger/validation_reflection), true is returned
    #   if the validates_presence_of macro has been used in the class for this attribute, or false
    #   otherwise.
    #
    # * if the :required option isn't provided, and the plugin isn't available, the value of the
    #   configuration option @@all_fields_required_by_default is used.
    #
    def method_required?(attribute) #:nodoc:
      if @object && @object.class.respond_to?(:reflect_on_all_validations)
        attribute_sym = attribute.to_s.sub(/_id$/, '').to_sym

        @object.class.reflect_on_all_validations.any? do |validation|
          validation.macro == :validates_presence_of && validation.name == attribute_sym
        end
      else
        @@all_fields_required_by_default
      end
    end

    # Generates error messages for the given method. Errors can be shown as list
    # or as sentence.
    #
    def errors_for(method, options)  #:nodoc:
      return nil unless @object && @object.respond_to?(:errors)

      # Ruby 1.9: Strings are not Enumerable, ie no String#to_a
      errors = @object.errors.on(method.to_s)
      errors.respond_to?(:to_a) ? errors.to_a : [errors]
    end

    # Generates a fieldset and wraps the content in an ordered list. When working
    # with nested attributes (in Rails 2.3), it allows %i as interpolation option
    # in :name. So you can do:
    #
    #   f.inputs :name => 'Task #%i', :for => :tasks
    #
    # And it will generate a fieldset for each task with legend 'Task #1', 'Task #2',
    # 'Task #3' and so on.
    #
    def field_set_and_list_wrapping(wrapper, html_options, contents='', &block) #:nodoc:
      legend  = html_options.delete(:name).to_s
      legend %= parent_child_index(html_options[:parent]) if html_options[:parent]
      locals = {:html => html_options, :legend => legend}
      block = lambda { contents } unless block_given?
      template.render :layout => find_template("#{wrapper}_wrapper", "wrapper"), :locals => locals, &block
      nil # don't return the rendered partial - it has already been rendered
    end

    # For methods that have a database column, take a best guess as to what the input method
    # should be.  In most cases, it will just return the column type (eg :string), but for special
    # cases it will simplify (like the case of :integer, :float & :decimal to :numeric), or do
    # something different (like :password and :select).
    #
    # If there is no column for the method (eg "virtual columns" with an attr_accessor), the
    # default is a :string, a similar behaviour to Rails' scaffolding.
    #
    def default_input_type(method) #:nodoc:
      return :string if @object.nil?

      column = @object.column_for_attribute(method) if @object.respond_to?(:column_for_attribute)

      if column
        # handle the special cases where the column type doesn't map to an input method
        return :time_zone if column.type == :string && method.to_s =~ /time_zone/
        return :select    if column.type == :integer && method.to_s =~ /_id$/
        return :datetime  if column.type == :timestamp
        return :numeric   if [:integer, :float, :decimal].include?(column.type)
        return :password  if column.type == :string && method.to_s =~ /password/

        # otherwise assume the input name will be the same as the column type (eg string_input)
        return column.type
      else
        obj = @object.send(method) if @object.respond_to?(method)

        return :select   if find_reflection(method)
        return :file     if obj && @@file_methods.any? { |m| obj.respond_to?(m) }
        return :password if method.to_s =~ /password/
        return :string
      end
    end

    # Used by select and radio inputs. The collection can be retrieved by
    # three ways:
    #
    # * Explicitly provided through :collection
    # * Retrivied through an association
    # * Or a boolean column, which will generate a localized { "Yes" => true, "No" => false } hash.
    #
    # If the collection is not a hash or an array of strings, fixnums or arrays,
    # we use label_method and value_method to retreive an array with the
    # appropriate label and value.
    #
    def find_collection_for_column(column, options)
      reflection = find_reflection(column)

      collection = if options[:collection]
        options.delete(:collection)
      elsif reflection || column.to_s =~ /_id$/
        parent_class = if reflection
          reflection.klass
        else
          ::ActiveSupport::Deprecation.warn("The _id way of doing things is deprecated. Please use the association method (#{column.to_s.sub(/_id$/,'')})", caller[3..-1])
          column.to_s.sub(/_id$/,'').camelize.constantize
        end

        parent_class.find(:all)
      else
        create_boolean_collection(options)
      end

      collection = collection.to_a if collection.instance_of?(Hash)

      # Return if we have an Array of strings, fixnums or arrays
      return collection if collection.instance_of?(Array) &&
                           [Array, Fixnum, String, Symbol].include?(collection.first.class)

      label = options.delete(:label_method) || detect_label_method(collection)
      value = options.delete(:value_method) || :id

      collection.map { |o| [o.send(label), o.send(value)] }
    end

    # Detected the label collection method when none is supplied using the
    # values set in @@collection_label_methods.
    #
    def detect_label_method(collection) #:nodoc:
      @@collection_label_methods.detect { |m| collection.first.respond_to?(m) }
    end

    # Returns a hash to be used by radio and select inputs when a boolean field
    # is provided.
    #
    def create_boolean_collection(options)
      options[:true] ||= I18n.t('yes', :default => 'Yes', :scope => [:formtastic])
      options[:false] ||= I18n.t('no', :default => 'No', :scope => [:formtastic])
      options[:value_as_class] = true unless options.key?(:value_as_class)

      { options.delete(:true) => true, options.delete(:false) => false }
    end

    # Used by association inputs (select, radio) to generate the name that should
    # be used for the input
    #
    #   belongs_to :author; f.input :author; will generate 'author_id'
    #   has_many :authors; f.input :authors; will generate 'author_ids'
    #   has_and_belongs_to_many will act like has_many
    #
    def generate_association_input_name(method)
      if reflection = find_reflection(method)
        method = method.to_s.singularize if [:has_and_belongs_to_many, :has_many].include?(reflection.macro)
        method = "#{method}_id"
        method = method.pluralize if [:has_and_belongs_to_many, :has_many].include?(reflection.macro)
      end
      method
    end

    # If an association method is passed in (f.input :author) try to find the
    # reflection object.
    #
    def find_reflection(method)
      @object.class.reflect_on_association(method) if @object.class.respond_to?(:reflect_on_association)
    end

    # Generate the html id for the li tag.
    # It takes into account options[:index] and @auto_index to generate li
    # elements with appropriate index scope. It also sanitizes the object
    # and method names.
    #
    def generate_html_id(method_name, value='input')
      if options.has_key?(:index)
        index = "_#{options[:index]}"
      elsif defined?(@auto_index)
        index = "_#{@auto_index}"
      else
        index = ""
      end
      sanitized_method_name = method_name.to_s.sub(/\?$/,"")

      "#{sanitized_object_name}#{index}_#{sanitized_method_name}_#{value}"
    end

    # Gets the nested_child_index value from the parent builder. In Rails 2.3
    # it always returns a fixnum. In next versions it returns a hash with each
    # association that the parent builds.
    #
    def parent_child_index(parent)
      duck = parent[:builder].instance_variable_get('@nested_child_index')

      if duck.is_a?(Hash)
        child = parent[:for]
        child = child.first if child.respond_to?(:first)
        duck[child].to_i + 1
      else
        duck.to_i + 1
      end
    end

    def sanitized_object_name
      @sanitized_object_name ||= @object_name.to_s.gsub(/\]\[|[^-a-zA-Z0-9:.]/, "_").sub(/_$/, "")
    end

    def humanized_attribute_name(method)
      if @object && @object.class.respond_to?(:human_attribute_name)
        @object.class.human_attribute_name(method.to_s)
      else
        method.to_s.send(@@label_str_method)
      end
    end

  end

  # Wrappers around form_for (etc) with :builder => SemanticFormBuilder.
  #
  # * semantic_form_for(@post)
  # * semantic_fields_for(@post)
  # * semantic_form_remote_for(@post)
  # * semantic_remote_form_for(@post)
  #
  # Each of which are the equivalent of:
  #
  # * form_for(@post, :builder => Formtastic::SemanticFormBuilder))
  # * fields_for(@post, :builder => Formtastic::SemanticFormBuilder))
  # * form_remote_for(@post, :builder => Formtastic::SemanticFormBuilder))
  # * remote_form_for(@post, :builder => Formtastic::SemanticFormBuilder))
  #
  # Example Usage:
  #
  #   <% semantic_form_for @post do |f| %>
  #     <%= f.input :title %>
  #     <%= f.input :body %>
  #   <% end %>
  #
  # The above examples use a resource-oriented style of form_for() helper where only the @post
  # object is given as an argument, but the generic style is also supported if you really want it,
  # as is forms with inline objects (Post.new) rather than objects with instance variables (@post):
  #
  #   <% semantic_form_for :post, @post, :url => posts_path do |f| %>
  #     ...
  #   <% end %>
  #
  #   <% semantic_form_for :post, Post.new, :url => posts_path do |f| %>
  #     ...
  #   <% end %>
  #
  # The shorter, resource-oriented style is most definitely preferred, and has recieved the most
  # testing to date.
  #
  # Please note: Although it's possible to call Rails' built-in form_for() helper without an
  # object, all semantic forms *must* have an object (either Post.new or @post), as Formtastic
  # has too many dependencies on an ActiveRecord object being present.
  #
  module SemanticFormHelper
    @@builder = Formtastic::SemanticFormBuilder

    # cattr_accessor :builder
    def self.builder=(val)
      @@builder = val
    end

    [:form_for, :fields_for, :form_remote_for, :remote_form_for].each do |meth|
      src = <<-END_SRC
        def semantic_#{meth}(record_or_name_or_array, *args, &proc)
          options = args.extract_options!
          options[:builder] = @@builder
          options[:html] ||= {}

          class_names = options[:html][:class] ? options[:html][:class].split(" ") : []
          class_names << "formtastic"
          class_names << case record_or_name_or_array
            when String, Symbol then record_or_name_or_array.to_s               # :post => "post"
            when Array then record_or_name_or_array.last.class.to_s.underscore  # [@post, @comment] # => "comment"
            else record_or_name_or_array.class.to_s.underscore                  # @post => "post"
          end
          options[:html][:class] = class_names.join(" ")

          #{meth}(record_or_name_or_array, *(args << options), &proc)
        end
      END_SRC
      module_eval src, __FILE__, __LINE__
    end
  end
end

