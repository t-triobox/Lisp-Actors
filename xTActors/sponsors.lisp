;; sponsors.lisp -- Sponsored Actors = dedicated threads running message dispatch
;;
;; Sponsors have use in setting up dedicated I/O port handlers which have to undergo
;; indefnite periods of blocking wait on the port. By isolating Actors to such a Sponsor
;; we avoid tying up other dispatch loops waiting for an Actor to clear for execution.
;; Message sends to sponsored Actors is fast, being just a mailbox send.
;;
;; DM/RAL 01/22
;; -----------------------------------------------------------------------------

(in-package :com.ral.actors.base)

(defvar *current-sponsor*  nil)

(define-symbol-macro self-sponsor  *current-sponsor*)

(def-beh sponsor-beh (mbox thread)
  ((:shutdown)
   (mp:process-terminate thread)
   (become (sink-beh)))
  
  ((actor . msg) when (actor-p actor)
   (mp:mailbox-send mbox (msg actor msg))))

(defun make-sponsor (name)
  (let* ((spon   (create))
         (mbox   (mp:make-mailbox))
         (thread (mp:process-run-function name () 'run-sponsor spon mbox)))
    (setf (actor-beh spon) (sponsor-beh mbox thread))
    spon))

(defun in-sponsor (spon actor)
  (if spon
      (actor (&rest msg)
        (send* spon actor msg))
    actor))

(defun in-this-sponsor (actor)
  (in-sponsor self-sponsor actor))

(defun run-sponsor (*current-sponsor* mbox)
  #F
  ;; Single-threaded - runs entirely in the thread of the Sponsor.
  ;;
  ;; We still need to abide by the single-thread-only exclusive
  ;; execution of Actors. There might be several other instances of
  ;; this running, or else some of the multithreaded versions.
  ;;
  ;; SENDs are optimistically committed in the event queue. In case of
  ;; error these are rolled back.
  ;;
  (let (qhd qtl qsav evt pend-beh)
    (macrolet ((addq (evt)
                 `(setf qtl
                        (if qhd
                            (setf (msg-link (the msg qtl)) ,evt)
                          (setf qhd ,evt)))
                 )
               (qreset ()
                 `(if (setf qtl qsav)
                      (setf (msg-link (the msg qtl)) nil)
                    (setf qhd nil))))
      (flet ((%send (actor &rest msg)
               (cond (evt
                      ;; reuse last message frame if possible
                      (setf (msg-actor (the msg evt)) (the actor actor)
                            (msg-args  (the msg evt)) msg
                            (msg-link  (the msg evt)) nil))
                     (t
                      (setf evt (msg (the actor actor) msg))) )
               (addq evt)
               (setf evt nil))

             (%become (new-beh)
               (setf pend-beh new-beh)))
        
        (declare (dynamic-extent #'%send #'%become))
        
        (let ((*current-actor*    nil)
              (*current-message*  nil)
              (*current-behavior* nil)
              (*send*             #'%send)
              (*become*           #'%become))
          (declare (list *current-message*))
          
          (loop
             (with-simple-restart (abort "Handle next event")
               (handler-bind
                   ((error (lambda (c)
                             (declare (ignore c))
                             (qreset)) ;; unroll SENDs
                           ))
                 (loop
                    (when (mp:mailbox-not-empty-p mbox)
                      (let ((evt (mp:mailbox-read mbox)))
                        (addq evt)))
                    (if (setf evt qhd)
                        (setf qhd (msg-link (the msg evt)))
                      (setf evt (mp:mailbox-read mbox)))
                    (setf self      (msg-actor (the msg evt))
                          self-msg  (msg-args (the msg evt))
                          qsav      (and qhd qtl))
                    (tagbody
                     again
                     (setf pend-beh (actor-beh (the actor self))
                           self-beh pend-beh)
                     (apply (the function pend-beh) self-msg)
                     (cond ((or (eq pend-beh self-beh)
                                (sys:compare-and-swap (actor-beh (the actor self)) self-beh pend-beh)))

                           (t
                            ;; Actor was mutated beneath us, go again
                            (setf evt (or evt qtl))
                            (qreset)
                            (go again))
                           )))
                 )))
          )))))

