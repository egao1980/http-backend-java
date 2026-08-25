(defsystem "http-backend-java"
  :version "0.1.0"
  :description "Java HttpClient + WebSocket backends for http-protocol / ws-protocol (ABCL)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("http-protocol"
               "ws-protocol"
               "quri"
               "babel"
               "alexandria"
               "bordeaux-threads"
               "cl-base64")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "java")
               (:file "backend")
               (:file "websocket"))
  :in-order-to ((test-op (test-op "http-backend-java/tests")))
  :properties
  (:cl-repo (:provides ("http-backend-java") :ci (:sources (("quri" :ql) ("babel" :ql) ("alexandria" :ql) ("bordeaux-threads" :ql) ("cl-base64" :ql) ("rove" :ql))))))

(defsystem "http-backend-java/tests"
  :depends-on ("http-backend-java" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "backend-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
