
'GA SDK. Use only the public methods, not prefixed by "private_".
'To be used correctly, init should be called when the player is loaded. Then setContentMetadata
'should be called whenever the video content changes. The notification period for the video content
'should also be set by the user to one second if possible, for optimal event reporting.
'Finally, reportEventLoopExit should be called when the video display is exited for whatever reason(error,
'end of video, user exit, etc')
function GA() as Object
    return{

        '==================================PUBLIC API=============================================='
        'Initialization method : Should be called when the player is created

        init : function(GA_UID, TestMode = false as Boolean) as Void
            m.private_debugEnabled = TestMode
            m.contentMetadata = {} 'Video metadata (duration, Title, etc. Provided by the user
            m.liveContent = false 'A boolean that should be true when a live event is shown'
            m.dateTime = createObject("roDateTime") 'dateTime object used to compute the current time
            m.pendingEvents = []'List of pending events to be reported
            m.flushTime& = 0'Next time (in MS since epoch) where we should flush our events
            m.priorities = {LOW : 0, MEDIUM : 1, HIGH : 2} 'Event priorities
            m.priorityIntervals = [10000,5000,1000] 'Event time priority intervals in MS
            m.base = {} 'Base JSON object when send with each report request
            m.quarterDuration = 0 'the duration of quarter of the video
            m.quarterReported = False 'flag to handle the progress of a quarter report
            m.HalfReported = False 'flag to handle the progress of half video report
            m.ThreequartersReported = False 'flag to handle progress of three quarters report
            m.ProgressEndReported = False 'flag to handle progress of video end report
            m.ProgressEndDuration = 0 'the duration of 97% of the video to report end event
            m.videoStarted = False 'flag to keep video started status and not repeat it on rewind
            m.private_setGAData(GA_UID) 'init the xfer object to send data to GA

            m.notificationPeriod = 1 'Video notification in seconds. Should be set to 1 by the SDK user
            m.hasContentBeenDisplayed = false 'Set to true when the first video started event is received

            m.testMode = TestMode
            m.baseArrayObject = {} 'Copy of base json object created for testing'


            m.events = {
                            CONTENT_READY : { name:"contentReady",priority : m.priorities.HIGH}, ' Reported in setContentMetadata
                            PLAYBACK_STARTED : { name:"playbackStarted",priority : m.priorities.HIGH}, 'Reported at stream started event and resume playback

                            PLAYPROGRESS_STARTED  : { name:"playProgressStarted",priority : m.priorities.HIGH},'Reported at stream started event
                            PLAYPROGRESS_QUARTER  : { name:"playProgressQuarter",priority : m.priorities.HIGH},'Reported at 1/4 of playback progress
                            PLAYPROGRESS_HALF  : { name:"playProgressHalf",priority : m.priorities.HIGH},'Reported at 1/2 of playback progress
                            PLAYPROGRESS_THREE_QUARTERS  : { name:"playProgressThreeQuarters",priority : m.priorities.HIGH},'Reported at 3/4 of playback progress
                            PLAYPROGRESS_END  : { name:"playProgressEnd",priority : m.priorities.HIGH},'Reported at 97%of playback progress
                            PLAYBACK_FINISHED  : { name:"playbackFinished",priority : m.priorities.HIGH},'Reported at isFullResult event, playback finished

                            PLAYBACK_PAUSED : { name:"playbackPaused",priority : m.priorities.MEDIUM},'Reported at event Pause
                            PLAYBACK_FAILED : { name:"playbackFailed",priority : m.priorities.MEDIUM},'Reported at isRequestFailed
                            }
        end function


        'This method should be called everytime a new video is givent to the player.  The metadata
        '  should look like this : {duration : 42,assetId : "AdDgFFGgEergergwrrehEj",title: "Wonderfull Video"}
        setContentMetadata : function (metadata as Object) as Void
            m.contentMetadata = metadata
            'get quarter of duration to handle play progress events
            m.quarterDuration = m.contentMetadata.duration/4
            'get 97% of duration to handle playProgressEnd event
            m.ProgressEndDuration = (m.contentMetadata.duration/100)*97
            'If the conten t shown is live, the content metadata's duration is set to -1'
            if(m.contentMetadata.duration = -1)
                m.liveContent = true
            end if
            m.dateTime.mark()
            m.hasContentBeenDisplayed = false
            m.private_reportContentReady()
        end function

        'Should be called when show() is called on the video
        reportPlayRequested : function() as Void
            event = m.private_makeStandardEvent(m.events.PLAYBACK_STARTED.name)
            m.private_addPendingEvent(event,m.events.PLAYBACK_STARTED.priority)
        end function

        'This method should be called when the event loop if the video player is exited (for any reason)
        ' This allows the SDK to make sure all the events have been flushed to IQ
        reportEventLoopExit : function() as Void
            m.private_flushPendingEvents()
        end function

        'Allows the SDK to handle event and report them to GA.
        'This method should be called in every iteration of the event loop. The event loop should
        ' not have a latency higher than one second:
        '   - the notificationPeriod of the video should be set to one second'
        '   - the event should have a waiting timeout of one second (msg = wait(1000, video.GetMessagePort()))
        handleEvent: function(event) as Void
           'First we check if we got a videoScreenEvent or a VideoPlayerEvent
           if (type(event) = "roVideoScreenEvent") or (type(event) = "roVideoPlayerEvent") or ((type(event) = "roAssociativeArray") and (event.DoesExist("getType")))

                if event.isStreamStarted()
                    m.private_reportVideoStarted()
                else if event.isPaused()
                    m.private_reportVideoPaused()
                else if event.isPlaybackPosition()
                      m.private_reportPlayheadUpdate(event.GetIndex())
                else if event.isRequestFailed()
                      m.private_reportFailed()
                else if event.isStatusMessage()
                else if event.isFullResult()
                    m.private_reportFullPlayback()
                else if event.isPartialResult()
                else if event.isResumed()
                    m.private_reportResumed()
                end if
            end if
            'We flush the events if it is time
            m.private_flushPendingEventsIfNecessary()
        end function

        '===========================Private methods============================

        'Checks if it is time to flush the event and flushes them when necessary
        private_flushPendingEventsIfNecessary : function() as Void
           'We will look at the current time and the flush time, whis is the next time we should flush
           ' the events
           if (m.private_getCurrentTimeMS() > m.flushTime&)
                m.private_flushPendingEvents()
           end if
        end function

        'Returns the current time since Epoch in milliseconds
        private_getCurrentTimeMS : function()
            m.dateTime.mark()'Update the dateTime object with the current time
            currentTimeMS& = m.dateTime.AsSeconds()
            currentTimeMS& = currentTimeMS& * 1000 + m.dateTime.GetMilliseconds()
            return currentTimeMS&
        end function

        'Adds an event to the event list and computes a new flushTime& depending on its priority
        private_addPendingEvent : function(event as Object ,priority as Integer) as Void
            if priority > m.priorities.HIGH
                m.private_debug("GA : Wrong event priority entered :", priority)
                return
            end if

            eventsInQueue = m.pendingEvents.Count()

            if(eventsInQueue = 0)
                m.flushTime& = m.private_getCurrentTimeMS() + m.priorityIntervals[priority]
            else
                m.flushTime& = m.private_min(m.flushTime&, m.private_getCurrentTimeMS() + m.priorityIntervals[priority])
            end if

            m.pendingEvents.Push(event)
        end function

        'Event factory. A standard event is an event with the private_minimum info needed by GA
        private_makeStandardEvent : function(name as String) as Object
            baseEvent ={}
            m.dateTime.mark()
            baseEvent.setModeCaseSensitive()
            baseEvent.addReplace("eventCategory", "Ooyala")
            baseEvent.addReplace("eventAction", name)
            baseEvent.addReplace("eventLabel", m.contentMetadata.Title)
            'setting the current time in seconds to parse it as date on the reports, right now google supports only int values on this field
            baseEvent.addReplace("eventValue",m.dateTime.AsSeconds())'in case Google supports String for Event value, change it to date in String, m.dateTime.ToISOSTRING()
            return baseEvent
        end function

        'Creates a standard event and adds it to the pending list
        private_buildAndAddEventToPending : function(eventType as Object) as Void
            event = m.private_makeStandardEvent(eventType.name)
            m.private_addPendingEvent(event,eventType.priority)
        end function


        'Reports the video started event
        private_reportVideoStarted : function() as Void
            m.private_debug("Start event", invalid)
            if not m.videoStarted
              m.private_buildAndAddEventToPending(m.events.PLAYPROGRESS_STARTED)
              m.videoStarted = True
            else
                'if stream started and videoStarted, is a rewind-forward event and will manage it as Pause/Play
                m.private_reportResumed()
            end if
        end function

        'Reports the failed event
        private_reportFailed : function() as Void
            m.private_buildAndAddEventToPending(m.events.PLAYBACK_FAILED)
        end function

        'Reports the video paused event
        private_reportVideoPaused : function() as Void
            m.private_buildAndAddEventToPending(m.events.PLAYBACK_PAUSED)
        end function

        'Reports the video resumed event
        'we don't support directly a resume event, but the playback event is sent again per Ooyala-GA documentation
        private_reportResumed : function() as Void
            m.private_buildAndAddEventToPending(m.events.PLAYBACK_STARTED)
        end function

        'Reports the content ready event
        private_reportContentReady : function() as Void
            m.private_debug( "ContentReady", invalid)
            if m.hasContentBeenDisplayed = false
                m.private_buildAndAddEventToPending(m.events.CONTENT_READY)
                m.hasContentBeenDisplayed = true
            end if
        end function

        'reports when playback has finished
          private_reportPlaybackFinished: function() as Void
              m.private_debug( "Finished", invalid)
              m.private_buildAndAddEventToPending(m.events.PLAYBACK_FINISHED)
          end function

        'resets the status var that handles playprogress reports and videostart
        private_ResetVideoReportStatus : function() as Void
            m.quarterReported = false
            m.HalfReported = false
            m.ThreequartersReported = false
            m.ProgressEndReported = false
            m.videoStarted = false
        end function

        'Reports the playback finished event.
        private_reportFullPlayback : function() as Void
            m.private_debug("Full playback",invalid)
            ' We flush all the remaining events
            m.private_reportPlaybackFinished()
            m.private_flushPendingEvents()
            m.private_ResetVideoReportStatus()
        end function

        'Reports the current playhead position in seconds,
        'handles the quarter passed events
        private_reportPlayheadUpdate : function(position) as Void
            eventToReport = invalid
            if not m.liveContent
                if (position > m.quarterDuration) and not m.quarterReported
                      eventToReport = m.events.PLAYPROGRESS_QUARTER
                      m.quarterReported = True
                else if  (position > m.quarterDuration*2) and not m.HalfReported
                      eventToReport = m.events.PLAYPROGRESS_HALF
                      m.HalfReported = True
                else if (position  > m.quarterDuration*3) and not m.ThreequartersReported
                      eventToReport = m.events.PLAYPROGRESS_THREE_QUARTERS
                      m.ThreequartersReported = True
                else if (position  > m.ProgressEndDuration) and not m.ProgressEndReported
                      eventToReport = m.events.PLAYPROGRESS_END
                      m.ProgressEndReported = True
                end if
            end if

            if not eventToReport = invalid
                  event = m.private_makeStandardEvent(eventToReport.name)
                  m.private_addPendingEvent(event,eventToReport.priority)
            end if
        end function

        'Flushes the pending events
        private_flushPendingEvents : function() as Void
        m.private_debug("Flusing Events ",invalid)
            'Check first if there are events waiting to be sent
            if (m.pendingEvents.Count() > 0)
                'Set the current time of the request
                m.dateTime.mark()

                i = m.pendingEvents.count()
                pendingevents =  m.pendingEvents
                m.private_sendEventsToGA(pendingevents)

                'Reset the list of pending events
                m.pendingEvents =[]
            end if
        end function

        'This method takes a list of events and send them to GA
        private_sendEventsToGA : function(pendingevents) as Void
            for each event in pendingevents
              m.private_GAtrackEvent(event.eventCategory,event.eventAction,event.eventLabel,event.eventValue)
            end for
        end function

        'generates UUID for the user when it is not present on the device
        private_GenerateGuid: function () As String
            Return "" + m.private_GetRandomHexString(8) + "-" + m.private_GetRandomHexString(4) + "-" + m.private_GetRandomHexString(4) + "-" + m.private_GetRandomHexString(4) + "-" + m.private_GetRandomHexString(12) + ""
        end function

        'utility function to create UUID
         private_GetRandomHexString: function (length As Integer) As String
            hexChars = "0123456789ABCDEF"
            hexString = ""
            For i = 1 to length
                hexString = hexString + hexChars.Mid(Rnd(16) - 1, 1)
            Next
            Return hexString
        end function

        'utility to get random int for Google request to avoid cache
        private_GetRandomInt: function (length As Integer) As String
            hexChars = "0123456789"
            hexString = ""
            For i = 1 to length
                hexString = hexString + hexChars.Mid(Rnd(16) - 1, 1)
            Next
            Return hexString
        end function

        'retrieve User id from the device
         private_GetUserID: function () As String
            sec = CreateObject("roRegistrySection", "analytics")
            if sec.Exists("UserID")
                return sec.Read("UserID")
            endif
            return ""
        end function

        'saves the generated UUID on the device for the next session
         private_SetUserID: function () As String
         m.private_debug("Set user id",invalid)
            sec = CreateObject("roRegistrySection", "analytics")
            uuid = m.private_GenerateGuid()
            sec.Write("UserID", uuid)
            sec.Flush()
            Return uuid
        end function

        'sets the data needed for GA, manage UUID, Google endpoint and GA account id
        private_setGAData: function (AccountID as String) as Void
        m.private_debug("Init GA xfer data",invalid)
            m.Tracker = CreateObject("roAssociativeArray")
            m.Tracker.userID = m.private_GetUserID()
            m.Tracker.AccountID = AccountID

            if len(m.Tracker.userID) = 0 then
                m.Tracker.userID = private_SetUserID()
            endif
            m.Tracker.endpoint = "http://www.google-analytics.com/collect"
            m.xfer = CreateObject("roURLTransfer")
            m.xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
        end function

        'send the event to GA using the values as follows:
        ' EventCat = Event Category => in this case Ooyala
        ' EventAct = Event Action =>  the action triggered
        ' EventVal = Event Value => the current date in seconds
        private_GAtrackEvent: function (EventCat as String , EventAct as String , EventLab as String , EventVal as Integer) as Void
            payload = "v=1"
            payload = payload + "&cid=" + m.xfer.Escape(m.Tracker.userID)
            payload = payload + "&tid=" + m.Tracker.AccountID

            payload = payload + "&t=event"
            If Len(EventCat) > 0
            payload = payload + "&ec=" + EventCat
            end if
            If Len(EventAct) > 0
            payload = payload + "&ea=" + EventAct
            end if
            If Len(EventLab) > 0
            payload = payload + "&el=" + m.xfer.Escape(EventLab)
            end if
            If EventVal > 0
            payload = payload + "&ev=" + EventVal.ToStr()
            end if
            payload = payload + "&ds=roku"
            payload = payload + "&z="+m.private_GetRandomInt(10)
            m.xfer.SetURL(m.Tracker.endpoint+"?"+payload)
            m.private_debug("Request to GA: "+m.Tracker.endpoint+"?"+payload,invalid)
            response = m.xfer.GetToString()
        end function

        'Utility function to compare numbers
        private_min : function(a as Double, b as Double) as Double
            if (a > b)
                return b
            end if
            return a
        end function

        'Prints to the console if debugEnabled is true
        'Use invalid as obj if there is only text to display
        private_debug : function(text as String, obj as Object)
            if (m.private_debugEnabled = true)
                if(obj = invalid)
                    print "Ooyala Debug: ";text
                else
                    print text;obj
                end if
            end if

        end function

    }

end function
