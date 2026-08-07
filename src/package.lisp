(defpackage #:http-backend-java
  (:use #:cl #:http-protocol)
  (:import-from #:ws-protocol
                #:ws-backend
                #:ws-backend-p
                #:ws-client
                #:ws-client-headers
                #:ws-client-protocols
                #:ws-client-auth
                #:ws-client-verify
                #:ws-connection
                #:%connection-ready-state
                #:backend-ws-transports
                #:connect
                #:on-event
                #:send-text
                #:send-binary
                #:ping
                #:close-connection)
  (:export #:java-backend
           #:make-java-backend
           #:*java-http-client*))
(in-package #:http-backend-java)
