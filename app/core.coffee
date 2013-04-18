# > core.coffee
class KodeLectures.Core.Utils
  @notify = (message)=>
    @instance?.destroy()
    @instance = new KDNotificationView
      type : "mini"
      title: message

class KodeLectures.Core.LiveViewer

  {notify} = KodeLectures.Core.Utils

  @getSingleton: ()=> @instance ?= new @
  
  active: no
  
  #pistachios: /\{(\w*)?(\#\w*)?((?:\.\w*)*)(\[(?:\b\w*\b)(?:\=[\"|\']?.*[\"|\']?)\])*\{([^{}]*)\}\s*\}/g
  
  constructor: ()->
    @sessionId = KD.utils.uniqueId "kodepadSession"
  
  setPreviewView: (@previewView)->
    unless @mdPreview
      @previewView.addSubView @mdPreview = new KDView
        cssClass : 'has-markdown markdown-preview'
        partial : '<div class="info"><pre>When you run your code, you will see the results here</pre></div>'
    else 
      @mdPreview?.show() 
      @terminal?.hide()
    
  setSplitView: (@splitView)->
    
  setMainView: (@mainView)->
  
  previewCode: (code, execute, options)->
    return if not @active 
    if code or code is ''
    
      kiteController = KD.getSingleton "kiteController"

      {ioController,courses,lastSelectedCourse:course,lastSelectedItem:lecture} = @mainView
      
      ioController.runFile courses,course,lecture,execute, (err,res)=>
      
        @mainView.taskView.emit 'ResultReceived',res unless err
        
        {type,previewPath,coursePath} = options
       
        type ?= 'code-preview'
  
        # ======================
        # CODE-PREVIEW
        # ======================
        
        if type is 'code-preview'
          window.appView = @previewView
        
          if res is '' then text = '<div class="info"><pre>KodeLectures received an empty response but no error.</pre></div>'
          else text = if err then "<div class='error'><pre>#{err.message}</pre></div>" else "<div class='success'><pre>#{res}</pre></div>"
          try
            unless @mdPreview
              @previewView.addSubView @mdPreview = new KDView
                cssClass : 'has-markdown markdown-preview'
                partial : text
            else 
              @mdPreview.updatePartial text
          
          catch error
            notify error.message
          finally
            @mdPreview?.show()
            @terminal?.hide()
            delete window.appView
       
        # ======================
        # EXECUTE-HTML
        # ======================

        else if type is 'execute-html'

          window.appView = @previewView

          ioController.generateSymlinkedPreview previewPath, coursePath, (err,res,publicURL) =>
            console.log err if err
            console.log "Course preview path '#{previewPath}' symlinked to '#{publicURL}'" unless err
          
            partial ="<div class='result-frame'><iframe src='#{publicURL}'></iframe></div>"
        
            try
              unless @mdPreview
                @previewView.addSubView @mdPreview = new KDView
                  cssClass : 'has-markdown markdown-preview'
                  partial : partial
              else 
                @mdPreview.updatePartial partial
          
            catch error
              notify error.message
            finally
              @mdPreview?.show()
              @terminal?.hide()
              delete window.appView
        
        # ======================
        # TERMINAL
        # ======================

        else if type is 'terminal'
          console.log 'Terminal requested.'
          window.appView = @previewView
        
          sendCommand = (command)=>
            if @terminal.terminal?.server?.input
              @terminal.terminal?.server?.input command+"\n" unless command is ''
              KD.utils.defer => @terminal.emit 'click' # focus :)
            else console.log 'There is a connectivity problem with the terminal'  
          unless @terminal
              console.log 'Adding terminal. This should only happen once.'
              appStorage = new AppStorage 'KodeLectures', '1.0'
              appStorage.fetchStorage (storage)=>
                @previewView.addSubView @terminal = new WebTermView appStorage
                @terminal.setClass 'webterm'
                console.log 'Terminal added successfully.'
                @terminal.show()
                @mdPreview?.hide()   
                delete window.appView  

                # this is hacky. where did the connected event go?
                KD.utils.wait 2000, =>    
                  initialCommand = "cd 'Applications/KodeLectures.kdapp/courses/#{coursePath}'"
                  console.log 'Sending initial command to terminal',initialCommand
                  sendCommand initialCommand
                  KD.utils.defer => 
                    console.log 'Sending command to terminal',code
                    sendCommand code
                            
          else 
              console.log 'Send command to terminal',code
              sendCommand code     
              
              @terminal?.show()
              @mdPreview?.hide()   
              
              delete window.appView        
 

class KodeLectures.Views.TaskSubItemView extends KDListItemView
  constructor:->
    super
    
    {cssClass} = @getData()
    
    @setClass cssClass
    
    @header = new KDCustomHTMLView
      tagName : 'span'
      cssClass : 'text'
      click :=>
        @content.show()
  
    @content = new KDCustomHTMLView
      tagName : 'span'
      cssClass : 'data'
 
    @updateViews @getData() 
 
  updateViews:(data)->
    
    {title,content,headerHidden,contentHidden} = data
    {type,title:initialTitle,content:initialContent,contentHidden:initialContentHidden,headerHidden:initialHeaderHidden} = @getData()
    
    @header.updatePartial title or initialTitle
    
    contentPartial = switch type
      when 'lectureText','taskText','codeHint','codeHintText' then marked(content or initialContent)
      when 'embed' then if content.type is 'youtube' then """<iframe src="#{content.url}" frameborder="0" allowfullscreen></iframe>"""
    
    @content.updatePartial contentPartial
    
    headerHidden ?= initialHeaderHidden
    contentHidden ?= initialContentHidden
    
    if headerHidden then @header.hide() else @header.show()
    if contentHidden then @content.hide() else @content.show()
  
    unless type isnt 'embed' and content and content isnt '' or type is 'embed' and content?.url? 
      @hide() 
    else 
      @show()
  
  viewAppended :->
    @setTemplate @pistachio()
    @template.update()
  
  pistachio:->
    """
    {{> @header}}
    {{> @content}}
    """  

class KodeLectures.Views.TaskView extends JView
  {TaskSubItemView} = KodeLectures.Views
  setMainView: (@mainView)->

  constructor:->
    super
    @setClass 'task-view'
  
  
    {videoUrl,@codeHintText,@codeHint,embedType,@taskText,@lectureText} = @getData()
    @codeHint ?= ''
    @codeHintText ?= ''
    @taskText ?= ''
    @lectureText ?= ''
    
    @subItemController = new KDListViewController
      itemClass : TaskSubItemView
      delegate  : @
      
    @subItemList = @subItemController.getView()
        
    @subItemEmbed = @subItemController.addItem 
      type          : 'embed'
      title         : ''
      content       : 
        url         : videoUrl
        type        : embedType
      cssClass      : 'embed'
      contentHidden : no
      headerHidden  : yes

    @subItemLectureText = @subItemController.addItem
      type          : 'lectureText'
      title         : 'Lecture'
      content       : @lectureText
      cssClass      : 'lecture-text-view has-markdown'
      contentHidden : no
      headerHidden  : yes
    
    @subItemTaskText = @subItemController.addItem
      type          : 'taskText'
      title         : 'Assignment'
      content       : @taskText
      cssClass      : 'task-text-view has-markdown'
      contentHidden : no
    
    @subItemHintText = @subItemController.addItem
      type          : 'codeHintText'
      title         : 'Hint'
      content       : @codeHintText
      cssClass      : 'hint-view has-markdown'
      contentHidden : yes
    
    @subItemHintCode = @subItemController.addItem
      type          : 'codeHint'
      title         : 'Solution'
      content       : @codeHint
      cssClass      : 'hint-code-view has-markdown' 
      contentHidden : yes
  
    @nextLectureButton = new KDButtonView
      title : 'Next Lecture'
      cssClass : 'cupid-green hidden fr task-next-button'
      callback :=>
        @mainView.emit 'NextLectureRequested'
 
    @resultView = new KDView
      cssClass : 'result-view hidden'
         
    @on 'LectureChanged',(lecture)=>
      
      
      {@codeHint,@codeHintText,@taskText,@lectureText,videoUrl,embedType}=lecture
      @setData lecture
      @resultView.hide()
      @nextLectureButton.hide()
      @mainView.liveViewer.active = no
      @mainView.liveViewer.mdPreview?.updatePartial '<div class="info"><pre>When you run your code, you will see the results here</pre></div>'
      
      @subItemEmbed.updateViews
        content       : 
          url         : videoUrl
          type        : embedType
        headerHidden  : yes
      
      @subItemLectureText.updateViews
        content : @lectureText
      
      @subItemTaskText.updateViews
        content : @taskText
      
      @subItemHintText.updateViews
        content : @codeHintText
      
      @subItemHintCode.updateViews
        content : @codeHint
      
      @render()
    
    @on 'ResultReceived', (result)=>
      
      {expectedResults,submitSuccess,submitFailure} = @getData()
      
      @resultView.show() unless expectedResults is null
      
      if result.trim() is expectedResults
        @resultView.updatePartial submitSuccess
        @resultView.setClass 'success'
        @nextLectureButton.show()
      else 
        @resultView.updatePartial submitFailure
        @resultView.unsetClass 'success'  
 
    @on 'ReadyForNextLecture', =>
      @nextLectureButton.show()
  
    @on 'HideNextLectureButton', =>
      @nextLectureButton.hide()
 
  pistachio:->
    """
    {{> @nextLectureButton}}
    {{> @resultView }}    
    {{> @subItemList}}
    """
class KodeLectures.Views.TaskOverviewListItemView extends KDListItemView
    
  constructor:->
    super
    @setClass 'task-overview-item has-markdown'
    
    {title,summary} = @getData()
    
    @titleText = new KDView
      cssClass : 'title-text'
      partial : marked title
      
    @summaryText = new KDView
      partial : marked summary
    
  pistachio:->
    """
    <span class='data'>
    {{> @titleText}}
    </span>
    <div class='summary'>
      <span class='data'>
      {{> @summaryText}}
      </span>
    </div>
    """
  click:->
    @getDelegate().emit 'OverviewLectureClicked',@
    
  viewAppended :->
    @setTemplate @pistachio()
    @template.update()
    
class KodeLectures.Views.TaskOverview extends JView
  {TaskOverviewListItemView} = KodeLectures.Views
  constructor:->
    super
    @setClass 'task-overview'
    
    @lectureListController = new KDListViewController
      itemClass : TaskOverviewListItemView
      delegate : @
      #wrapper     : no
      #scrollView  : yes
      #keyNav      : yes
      #view        : new KDListView
        #keyNav    : yes
        #delegate  : @
        #cssClass  : "task-overview-item"
        #itemClass : TaskOverviewListItemView
    , items       : @getData()
 
    @lectureList = @lectureListController.getView()
    
    @lectureListController.listView.on 'OverviewLectureClicked', (item)=>
      @mainView.emit 'LectureChanged',@lectureListController.itemsOrdered.indexOf item 
    
    @on 'LectureChanged', ({course,index})=>
      
      @lectureListController.removeAllItems()
      @lectureListController.instantiateListItems course.lectures
      
      item.unsetClass 'active' for item in @lectureListController.itemsOrdered 
      @lectureListController.itemsOrdered[index].setClass 'active'
  
  setMainView:(@mainView)->
  
  pistachio:->
    """
    {{> @lectureList}}
    """

class KodeLectures.Views.CourseLectureListItemView extends KDListItemView
  
  constructor:->
    super
    
    @lectureTitle = new KDView 
      cssClass : 'lecture-listitem'
      partial : @getData().title
  
  viewAppended :->
    @setTemplate @pistachio()
    @template.update()
  
  pistachio:->
    """
    {{> @lectureTitle}}
    """
  
  click:(event)->
    event.stopPropagation()
    event.preventDefault()
    @getDelegate().emit 'LectureSelected', @getData()
    
    
class KodeLectures.Views.CourseSelectionItemView extends KDListItemView  
  {CourseLectureListItemView} = KodeLectures.Views
  constructor:->
    super
    @setClass 'selection-listitem'

    lectureCount = @getData().lectures.length
    
    @titleText = new KDView
      partial   : "<span>#{@getData().title}</span><span class='lectures'>#{lectureCount} lecture#{if lectureCount is 1 then '' else 's'}</span>"
      cssClass  : 'title'
      
    @descriptionText = new KDView
      partial   : @getData().description
      cssClass  : 'description'
  
    @lectureController = new KDListViewController
      itemClass : CourseLectureListItemView
      delegate  : @ 
    , items     : @getData().lectures
    @lectureList = @lectureController.getView()
  
    @lectureController.listView.on 'LectureSelected', (data)=>
      @getDelegate().emit 'LectureSelected', {lecture:data, course:@getData()}
      
    @titleText.addSubView @settingsButton = new KDButtonView
      style               : 'course-settings-menu editor-advanced-settings-menu fr'
      icon                : yes
      iconOnly            : yes
      iconClass           : "cog"
      callback            : (event)=>

        contextMenu       = new JContextMenu
          event           : event
          delegate        : @
        ,

        'Remove Course'   :
          callback        : (source, event)=>
            contextMenu.destroy()
            modal         = new KDModalView
              cssClass    : 'lecture-modal'
              title       : 'Remove Course'
              content     : 'Do you really want to remove this course and all its files? All the changes you made will be deleted alongside the lectures. You will have to re-import the course to open it again.'
              buttons     :
                "Remove Course completely":
                  title   : 'Remove Course completely'
                  cssClass: 'modal-clean-red'
                  callback: =>
                    @getDelegate().emit 'RemoveCourseClicked',{course:@getData(),view:@}
                    modal.destroy()
                Cancel    :
                  cssClass: 'modal-cancel'
                  title   : 'Cancel'
                  callback: =>
                    modal.destroy()
                
        'Reset Course files':
          callback        : (source, event)=>                
            contextMenu.destroy()
            
            if @getData().originType in ['git']
             modal         = new KDModalView
              cssClass    : 'lecture-modal'              
              title       : 'Reset Course Files'
              content     : 'Do you really want to reset all files in this course? All the changes you made will be deleted. The course will revert to the stage it was in when it was imported.'
              buttons     :
                "Reset all files":
                  title   : 'Reset all files'
                  cssClass: 'modal-clean-red'
                  callback: =>
                    console.log 'Resetting'
                    @getDelegate().emit 'ResetCourseClicked',{course:@getData(),view:@}
                    contextMenu.destroy()
                    modal.destroy()
                Cancel    :
                  cssClass: 'modal-cancel'
                  title   : 'Cancel'
                  callback: =>
                    modal.destroy()
            else new KDNotificationView {title:'This Course can not be reset. Try deleting and re-importing it.'}
                
    @firstLectureLink = new KDCustomHTMLView
      partial : 'Get started!'
      cssClass : 'get-started-link'
      click   : (event)=>
        event.preventDefault()
        event.stopPropagation()
        @getDelegate().emit 'LectureSelected', {lecture:@getData().lectures[0], course:@getData()}
      
  
  viewAppended :->
    @setTemplate @pistachio()
    @template.update()
  
  click:(event)->
    event.stopPropagation()
    event.preventDefault()
    @getDelegate().emit 'CourseSelected', @getData()
  
  pistachio:->
   
    # {{> @lectureList }}
    """
    {{> @titleText}}
    <div class="course-details">
    {{> @descriptionText}}
    {{> @firstLectureLink}}
    </div>
    """
class KodeLectures.Views.ImportCourseRecommendedListItemView extends KDListItemView    
  
  constructor:->
    super
    
    @setClass 'recommended-listitem'
    
    @importButton = new KDButtonView
      cssClass : 'cupid-green recommended-import-button'
      title :'Import this Course'
      callback :=>
        @getDelegate().emit 'ImportClicked',@getData()
    
    @iconView = new KDView
     cssClass : 'recommended-icon'
    
    
    
  viewAppended :->
    @setTemplate @pistachio()
    @template.update()
      
  pistachio:->
    """
    {{> @iconView}}
    {{> @importButton}}
    {{ #(title)}}
    {{ #(description)}}
    """
    
class KodeLectures.Views.ImportCourseBar extends JView
  {ImportCourseRecommendedListItemView} = KodeLectures.Views
  constructor:->
    super
    
    @apiURL = 'http://arvidkahl.koding.com/lectures'
    
    @recommendedHeader = new KDView
      cssClass : 'recommended-courses'
      partial:"<h1><strong>Recommended</strong> Courses</h1>"
      click :=>
        if @$().hasClass 'minimized'
          @unsetClass 'minimized'
        else @setClass 'minimized'
      
    
    @recommendedListController = new KDListViewController
      itemClass : ImportCourseRecommendedListItemView
    
    @recommendedList = @recommendedListController.getView()
    @recommendedListController.listView.on 'ImportClicked', (data)=>
      @getDelegate().emit 'ImportRequested', data
    
    @getSingleton('kiteController').run "curl -kL '#{@apiURL}'", (error, data)=>
      
      # if any error exists or data is empty, try JSONP
      if error or not data
        json = $.ajax 
          url         : "#{apiURL}"
          data        : {}
          dataType    : "jsonp"
          success     : callback
      
      # parse the curl result.
      try json = JSON.parse data
      #console.log json
      
      if json?.courses?.length 
        for course in json.courses
          @recommendedListController.addItem course
      
  pistachio:->
    """
    {{> @recommendedHeader}}
    {{> @recommendedList}}
      
    """
    

class KodeLectures.Views.NavBar extends JView

  constructor:->
    super
    @setClass 'nav-bar'
    
    
    @aboutLink = new KDCustomHTMLView
      partial : 'About'
      cssClass : 'nav-link about'
      click:=>
        @getDelegate().emit 'AboutLinkClicked'
        
    @coursesLink = new KDCustomHTMLView
      partial : 'My Courses'
      cssClass : 'nav-link courses'
      click:=>
        @getDelegate().emit 'CoursesLinkClicked'
        
    @recommendedLink = new KDCustomHTMLView
      partial : 'Recommended Courses'
      cssClass : 'nav-link recommended'
      click:=>
        @getDelegate().emit 'RecommendedLinkClicked'
    
  pistachio:->
    """
    <div class='logo'><span class='icon'></span>Kode<span>Lectures</span></div>
      {{> @aboutLink}}
      {{> @coursesLink}}
      {{> @recommendedLink}}
    """

class KodeLectures.Views.CourseSelectionView extends JView
  {CourseSelectionItemView, ImportCourseBar, NavBar} = KodeLectures.Views
  
  constructor:->
    super
    courses = @getData()
    
    @courseController = new KDListViewController
      itemClass : CourseSelectionItemView
      delegate  : @
    , items     : courses
  
    @courseView = @courseController.getView()
    
    @courseEmptyMessage = new KDCustomHTMLView
      tagName : 'span'
      cssClass : 'course-empty-message'
      partial : """Hmm, you don't have any courses here yet. <span>You can import them from the list below or manually with the 'Import Course' button.</span>"""
    
    @on 'NewCourseImported', (course)=>
      @courseController.addItem course
      courses.push course
      @courseEmptyMessage.hide()
    
    @courseController.listView.on 'LectureSelected', ({course,lecture})=>
      @mainView.emit 'CourseChanged', courses.indexOf course
      KD.utils.defer => @mainView.emit 'LectureChanged', course.lectures.indexOf lecture
    
    @courseController.listView.on 'CourseSelected', (course)=>
      @mainView.emit 'CourseChanged', courses.indexOf course
      KD.utils.defer => @mainView.emit 'LectureChanged', 0

    @courseController.listView.on 'RemoveCourseClicked', ({course,view})=>
      @mainView.ioController.removeCourse courses, courses.indexOf(course), (err,res)=>
        unless err then view.destroy()
        courses.splice courses.indexOf(course),1
        if courses.length is 0 then @courseEmptyMessage.show()
    
    @courseController.listView.on 'ResetCourseClicked', ({course,view})=>
      @mainView.ioController.resetCourseFiles courses, courses.indexOf(course), course.originType, (err,res)=>
        unless err then new KDNotificationView {title:'Files successfully reset'}
    
    @on 'CoursesLinkClicked', =>
      @$().animate
         scrollTop: $(".page > div.course-header").offset().top-100
      , 1000
          
    @on 'AboutLinkClicked', =>
      @$().animate
         scrollTop: $(".page > div.about").offset().top-100
      , 1000
    
    @on 'RecommendedLinkClicked', =>
      @$().animate
         scrollTop: $(".page > div.import-course-bar").offset().top-100
      , 1000
    
    @on 'ImportRequested', (data)=>
      
      courseExists = course for course in courses when course.originUrl is data.url

      {title,type,url} = data

      if courseExists
        #new KDNotificationView
          #title : 'Course already exists.'
        modal = new KDModalView
          cssClass : 'lecture-modal'
          title : 'Import a Course'
          content : '<p>The Course you are trying to import is already installed. Do you want to replace the currently installed version?</p><p><strong>Warning</strong>: all your file changes will be lost!</p>'
          buttons :
            "Replace Course":
              title : "Replace Course #{course.title}"
              cssClass : 'modal-clean-red'
              callback : =>
                console.log "Removing old Course #{course.title}"
                modal.destroy()
                @mainView.ioController.removeCourse courses, courses.indexOf(course), (err,res)=>
                  item.destroy() for item in @courseController.itemsOrdered when item.getData().path is course.path
                  if type in ['git']
                    console.log 'Attempting import from',url
                    @mainView.ioController.importCourseFromRepository url, type, =>
                      console.log 'Import started.'
            Cancel :
              title : 'Keep the old Course'
              cssClass : 'modal-cancel'
              callback : =>
                modal.destroy()
                      
  
      else 
        if type in ['git']
          console.log 'Attempting import from ',url
          @mainView.ioController.importCourseFromRepository url, type, =>
            console.log 'Import completed successfully.'
    
    @courseHeader = new KDView
      cssClass : 'course-header'
      partial : '<h1><strong>Your</strong> Courses</h1>'

    @importCourseBar = new ImportCourseBar
      cssClass : 'import-course-bar'
      delegate : @

    @navBar = new NavBar
      delegate : @

  setMainView:(@mainView)->

  pistachio:->
    """
    {{> @navBar}}
    
    <div class="hero">
      <div class="content">
        <span class='video'><iframe width="100%" height="100%" src="http://www.youtube.com/embed/fvsKkwbhfs8" frameborder="0" allowfullscreen></iframe></span>
        <span class='title'>Learn. Teach. Code.</span>
        <span class='subtitle'>KodeLectures will allow you to chose from a variety of user-submitted lectures or submit them yourself!</span>
      </div>
    </div>
    <div class="cta-header">
   
    </div>
    <div class="page">
      <div class='about'>
        <h1><strong>About</strong> <span>/ How to use KodeLectures</span></h1>
        <p>Welcome to KodeLectures! Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
        <h2>How do I learn?</h2>
        <p>Welcome to KodeLectures! Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
        <h2>How do I teach?</h2>
        <p>Welcome to KodeLectures! Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
      </div>
      <hr/>
      {{> @courseHeader}}
      {{> @courseEmptyMessage}}
      {{> @courseView}}
      <hr/>
      {{> @importCourseBar}}
      <hr/>
    </div>
    """