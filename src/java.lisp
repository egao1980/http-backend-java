(in-package #:http-backend-java)

;;; Thin ABCL ↔ java.net.http helpers.

#-abcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (warn "http-backend-java: designed for ABCL (java.net.http)."))

#+abcl
(progn
  (defun %jcall (method obj &rest args)
    (apply #'java:jcall method obj args))

  (defun %jstatic (method class &rest args)
    (apply #'java:jstatic method class args))

  (defun %octets-to-jbytes (vec)
    "CL octet vector → Java byte[]."
    (let* ((v (coerce vec '(simple-array (unsigned-byte 8) (*))))
           (n (length v))
           (arr (java:jnew-array "byte" n)))
      (dotimes (i n)
        (let ((b (aref v i)))
          (setf (java:jarray-ref arr i)
                (if (> b 127) (- b 256) b))))
      arr))

  (defun %jbytes-to-octets (jarr)
    "Java byte[] → (simple-array (unsigned-byte 8) (*))."
    (let* ((n (java:jarray-length jarr))
           (out (make-array n :element-type '(unsigned-byte 8))))
      (dotimes (i n)
        (let ((b (java:jarray-ref jarr i)))
          (setf (aref out i) (logand b #xff))))
      out))

  (defun %headers-to-alist (jheaders)
    "java.net.http.HttpHeaders → alist of (downcase-name . value-string)."
    (let* ((map (%jcall "map" jheaders))
           (keys (%jcall "keySet" map))
           (iter (%jcall "iterator" keys))
           (out nil))
      (loop while (%jcall "hasNext" iter)
            do (let* ((name0 (%jcall "next" iter))
                      (name (string-downcase (princ-to-string name0)))
                      (vals (%jcall "get" map name0))
                      (joined (format nil "~{~A~^, ~}"
                                      (loop for i below (%jcall "size" vals)
                                            collect (%jcall "get" vals i)))))
                 (push (cons name joined) out)))
      (nreverse out)))

  (defun %alist-to-ht (alist)
    (let ((ht (make-hash-table :test #'equal)))
      (dolist (pair alist ht)
        (setf (gethash (car pair) ht) (cdr pair)))))
) ; progn #+abcl
