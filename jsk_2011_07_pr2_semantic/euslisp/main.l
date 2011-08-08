#!/usr/bin/env roseus

(load "package://jsk_maps/src/eng2-scene.l")
(load "package://pr2eus/pr2-interface.l")
(load "knowrob-interface.l") ;; -> json_prolog/src
(load "actions.l")

(ros::roseus "demo_main")

(defun init ()
  ;; env
  ;;  (setq *scene* (make-eng2-scene))
  (unless (boundp '*pr2*) (pr2))
  (unless (boundp '*ri*) (setq *ri* (instance pr2-interface :init)))
  (unless (boundp '*tfl*)(setq *tfl* (instance ros::transform-listener :init)))
  (setq *prolog* (instance json_prolog :init "json_prolog"))
  ;; callbacks
  (ros::subscribe "/query" std_msgs::string #'identity)
  (change-inflation-range 0.4)
  )

(defun insert-robot-pose ()
  (let (pose po ret
             (type "'http://ias.cs.tum.edu/kb/knowrob.owl#Robot'")
             (robot "'http://www.jsk.t.u-tokyo.ac.jp/jsk_map.owl#pr2'"))
    (ros::spin-once)
    (setq pose (send *tfl* :lookup-transform "/map" "/base_footprint" (ros::time 0)))
    (send pose :locate (scale 0.001 (send pose :worldpos)) :world)
    (setq po (coerce (array-entity (send pose :4x4)) cons))
    (setq po (mapcan #'(lambda(x)(coerce (format nil ",~a" x) cons)) po))
    (setq po (coerce (cdr po) string))
    (send *prolog* :query
	  (list->prolog `((create_object_instance ,type ,robot)))) ;; always success
    (setq ret (send *prolog* :query
		    (list->prolog `((update_pose ,robot ,(format nil "[~a]" po))))))
    ret ))


;; ask to knowrob
(defun ask-query-and-move (&optional (type "Cup") (name nil))
  (let* (solutions pose opose flag)
    (ros::spin-once)
    (setq opose (send *tfl* :lookup-transform "/map" "/base_footprint" (ros::time 0)))
    (insert-robot-pose)
    (setq solutions (similar-objects-with-info-by-distance type))
    (dolist (solution solutions)
      (setq obj (cadr (assoc "OBJ" solution :test #'equal)))
      (setq robot-pose (cadr (assoc "POSE_SPOT" solution :test #'equal)))
      (ros::spin-once)
      (send *pr2* :angle-vector (send *ri* :state :potentio-vector))
      (send *pr2* :head :angle-vector #f(0 0))
      (send *pr2* :torso :angle-vector #f(0))
      (send *ri* :angle-vector (send *pr2* :angle-vector) 2000)
      (clear-costmap)
      (send *ri* :wait-interpolation)
      (send *ri* :move-to robot-pose) ;; robot moves
      (ros::spin-once)
      (send *pr2* :move-to (send *tfl* :lookup-transform "/map" "/base_footprint" (ros::time 0)) :world)
      (setq obj-pose (cadr (assoc "POSE_OBJ" solution :test #'equal)))
      (send *pr2* :head :look-at (send obj-pose :worldpos))
      (send *ri* :angle-vector (send *pr2* :angle-vector) 2000)
      (send *ri* :wait-interpolation)
      ;; grasp cup here
      (speak-jp "こっぷをさがしています")
      (let ((neck-av (send *pr2* :head :angle-vector)))
	(setq flag
	      (or (check :timeout 4 :type name)
		  (progn (send *pr2* :head :angle-vector (v+ #f(20 0) neck-av))
			 (send *ri* :angle-vector (send *pr2* :angle-vector) 500)
			 (send *ri* :wait-interpolation)
			 (check :timeout 4 :type name))
		  (progn (send *pr2* :head :angle-vector (v+ #f(-20 0) neck-av))
			 (send *ri* :angle-vector (send *pr2* :angle-vector) 500)
			 (send *ri* :wait-interpolation)
			 (check :timeout 4 :type name)))
	      ))
      (when flag
	(speak-jp "こっぷがみつかりました")
	(or (pick :larm)
	    (progn
	      (send *pr2* :head :look-at (send *obj* :worldpos))
	      (send *ri* :head-angle-vector (send *pr2* :angle-vector) 500)
	      (check :timeout 4 :type name)
	      (pick :larm)))
	;; go to somewhere
;	(pr2-tuckarm-pose :larm)
	(send *pr2* :angle-vector (send *ri* :state :potentio-vector))
	(send *pr2* :head :angle-vector #f(0 0))
	(send *pr2* :torso :angle-vector #f(0))
	(send *ri* :angle-vector (send *pr2* :angle-vector) 2000)
	(send *ri* :wait-interpolation)
	(clear-costmap)
	(send *ri* :move-to opose)
	(send *pr2* :head :look-at (send *pr2* :larm :end-coords :worldpos))
	(send *ri* :head-angle-vector (send *pr2* :angle-vector) 1000)
	(speak-jp "こっぷをもってきました")
	(hand-over)
	(return-from ask-query-and-move t))
      (speak-jp "こっぷはみつかりませんでした")
      (pr2-tuckarm-pose :larm)
      )
    (send *ri* :move-to opose)
    nil))

(defun demo (&rest args)
  (when (eq args nil)
    (warn "(:home) (:pick name) (:pick-kitchen name)~%")
    (return-from demo t))
  ;;
  (when (member :home args)
    (pr2-tuckarm-pose :larm)
    (send *ri* :move-to
	  (cadr (assoc "POSE_SPOT" (car (find-knowrob-objects-with-info "OfficeRoom")) :test #'equal))))
  ;;
  (when (member :pick args)
    (pr2-tuckarm-pose :larm)
    (change-inflation-range 0.20) (initialize-costmap)
    (ask-query-and-move "Cup" (cadr (member :pick args))))
  ;;
  (when (member :pick-kitchen args)
    (pr2-tuckarm-pose :larm)
    (change-inflation-range 0.20) (initialize-costmap)
    (ask-query-and-move "Cup" (cadr (member :pick-kitchen args))))
  )

;;
(progn
  (init)  ;; for pr2 setup
  (init2) ;; for cup detection
)
(warn ";;(demo :pick \"cmu\")")
;(ask-query-and-move "Cup")
;(ros::spin)
;(exit)
