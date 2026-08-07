(defpackage #:http-backend-java/tests
  (:use #:cl #:rove #:http-protocol #:http-backend-java))
(in-package #:http-backend-java/tests)

#+abcl
(deftest java-get-example-com
  (let* ((b (make-java-backend))
         (c (make-http-client b))
         (r (send b c (make-http-request :method :get
                                         :url "https://example.com/"))))
    (ok (= 200 (response-status r)))
    (ok (member (response-http-version r) '(:http/1.1 :http/2)))
    (ok (plusp (length (response-body r))))))

#-abcl
(deftest java-skipped-on-non-abcl
  (ok t))
