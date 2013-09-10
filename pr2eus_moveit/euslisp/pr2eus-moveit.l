(ros::load-ros-manifest "pr2eus_moveit")

(require :robot-interface "package://pr2eus/robot-interface.l")
(require :collision-object-publisher "package://pr2eus_moveit/euslisp/collision-object-publisher.l")

(defvar *moveit-error-code-list*
  (list
   (cons 1 "SUCCESS")
   (cons 99999 "FAILURE")
   ;;
   (cons -1 "PLANNING_FAILED")
   (cons -2 "INVALID_MOTION_PLAN")
   (cons -3 "MOTION_PLAN_INVALIDATED_BY_ENVIRONMENT_CHANGE")
   (cons -4 "CONTROL_FAILED")
   (cons -5 "UNABLE_TO_AQUIRE_SENSOR_DATA")
   (cons -6 "TIMED_OUT")
   (cons -7 "PREEMPTED")
   ;; planning & kinematics request errors
   (cons -10 "START_STATE_IN_COLLISION")
   (cons -11 "START_STATE_VIOLATES_PATH_CONSTRAINTS")
   ;;
   (cons -12 "GOAL_IN_COLLISION")
   (cons -13 "GOAL_VIOLATES_PATH_CONSTRAINTS")
   (cons -14 "GOAL_CONSTRAINTS_VIOLATED")
   ;;
   (cons -15 "INVALID_GROUP_NAME")
   (cons -16 "INVALID_GOAL_CONSTRAINTS")
   (cons -17 "INVALID_ROBOT_STATE")
   (cons -18 "INVALID_LINK_NAME")
   (cons -19 "INVALID_OBJECT_NAME")
   ;; system errors
   (cons -21 "FRAME_TRANSFORM_FAILURE")
   (cons -22 "COLLISION_CHECKING_UNAVAILABLE")
   (cons -23 "ROBOT_STATE_STALE")
   (cons -24 "SENSOR_INFO_STALE")
   ;; kinematics errors
   (cons -31 "NO_IK_SOLUTION")
   ))

(defclass moveit-environment
  :super propertied-object
  :slots (config-list
          scene-service
          planning-service
          execute-service
          robot
          default-frame-id default-link
          multi-dof-name multi-dof-frame
          ))

;; frame-id
;; multi-dof-joint name/frame-id
;; group-name -> joint-list, target-link
(defmethod moveit-environment
  (:init
   (&key ((:scene-service sc-srv) "/get_planning_scene")
         ((:planning-service pl-srv) "/plan_kinematic_path")
         ((:execute-service ex-srv) "/execute_kinematic_path")
         ((:robot rb) *pr2*) (frame-id "base_footprint") ;; frame-id needs to be contained in robot_model
         (multi-dof-joint-name "virtual_joint")
         (multi-dof-frame-id "odom_combined"))
   (setq scene-service sc-srv
         planning-service pl-srv
         execute-service ex-srv
         robot rb
         default-frame-id frame-id
         multi-dof-name multi-dof-joint-name
         multi-dof-frame multi-dof-frame-id)
   (setq default-link (send self :search-link-from-name frame-id))
   (setq config-list (send self :default-configuration))
   (unless (ros::ok)
     (ros::roseus "pr2eus_moveit_environment"))
   self)
  (:robot (&rest args) (forward-message-to robot args))
  (:sync-robot-model (rb &optional (change-argument nil))
   (let ((r-from (if change-argument robot rb))
         (r-to   (if change-argument rb robot)))
     (send r-to :reset-coords)
     (send r-to :transform (send r-from :worldcoords))
     (send r-to :angle-vector (send r-from :angle-vector))
     (send r-to :worldcoords)
     r-to))
  (:search-link-from-name
   (link-name)
   (cond
    ((find-method robot (intern (string-upcase (format nil "~A_lk" link-name)) *keyword-package*))
     (send robot (intern (string-upcase (format nil "~A_lk" link-name)) *keyword-package*)))
    ((find-method robot (intern (string-upcase link-name) *keyword-package*))
     (send robot (intern (string-upcase link-name) *keyword-package*)))
    (t
     (find-if #'(lambda (l) (cond ((symbolp (send l :name) (string= (symbol-string (send l :name)))))
                                  ((stirngp (send l :name) (string= (send l :name))))
                                  (t nil))) (send robot :links))
     )))
  (:copy-robot-state (rb)
   (send robot :reset-coords)
   (send robot :transform (send rb :worldcoords))
   (send robot :angle-vector (send rb :angle-vector))
   robot)
  (:default-configuration ()
   (list (list :rarm
               (cons :group-name "right_arm")
               (cons :target-link
                     (send self :search-link-from-name "r_wrist_roll_link"))
               (cons :joint-list (send robot :rarm :joint-list))
               )
         (list :larm
               (cons :group-name "left_arm")
               (cons :target-link
                     (send self :search-link-from-name "l_wrist_roll_link"))
               (cons :joint-list (send robot :larm :joint-list))
               )
         (list :rarm-torso
               (cons :group-name "right_arm_and_torso")
               (cons :target-link
                     (send self :search-link-from-name "r_wrist_roll_link"))
               (cons :joint-list (append (send robot :torso :joint-list) (send robot :rarm :joint-list)))
               )
         (list :larm-torso
               (cons :group-name "left_arm_and_torso")
               (cons :target-link
                     (send self :search-link-from-name "l_wrist_roll_link"))
               (cons :joint-list (append (send robot :torso :joint-list) (send robot :larm :joint-list)))
               )
         (list :arms ;; not implemented yet
               (cons :group-name "arms")
               (cons :target-link
                     (list (send self :search-link-from-name "l_wrist_roll_link")
                           (send self :search-link-from-name "r_wrist_roll_link")))
               (cons :joint-list (append (send robot :larm :joint-list)
                                         (send robot :rarm :joint-list)))
               )
#| ;; sample of pr2_moveit_config/config/pr2.srdf
    <group name="base">
        <joint name="world_joint" />
    </group>
    <group name="left_arm">
        <chain base_link="torso_lift_link" tip_link="l_wrist_roll_link" />
    </group>
    <group name="left_arm_and_torso">
        <chain base_link="base_link" tip_link="l_wrist_roll_link" />
    </group>
    <group name="right_arm">
        <chain base_link="torso_lift_link" tip_link="r_wrist_roll_link" />
    </group>
    <group name="right_arm_and_torso">
        <chain base_link="base_link" tip_link="r_wrist_roll_link" />
    </group>
    <group name="arms">
        <group name="left_arm" />
        <group name="right_arm" />
    </group>
    <group name="head">
        <joint name="head_pan_joint" />
        <joint name="head_tilt_joint" />
    </group>
    <group name="torso">
        <joint name="torso_lift_joint" />
    </group>
    <group name="whole_body">
        <group name="base" />
        <group name="arms" />
        <group name="torso"/>
    <group/>
|#
         ))
  (:worldcoords->default-frame-relative (wcds)
   (send (send default-link :worldcoords) :transformation
         (send wcds :worldcoords)))
  (:get-group-tip-coords (confkey) ;; get-robot-coords
   (let ((link-inst (cdr (assoc :target-link (cdr (assoc confkey config-list))))))
     (send link-inst :copy-worldcoords)))
  (:get-planning-scene (&optional (components 1023))
   (get-planning-scene :scene-service scene-service :components components))
  (:get-ik-for-pose
   (cds confkey &key (use-actual-seed t) (retry t)
        (end-coords) ;; (list :rarm :end-coords)
        (frame-id default-frame-id) (timeout 0.05) (scene)
        (attempts) (avoid-collision t) &allow-other-keys)
   (let ((tgt-cds (send cds :copy-worldcoords))
         (group-name (cdr (assoc :group-name (cdr (assoc confkey config-list)))))
         (joint-list (cdr (assoc :joint-list (cdr (assoc confkey config-list)))))
         scene rstate constraints)
     (when use-actual-seed
       (unless scene
         (setq scene (send self :get-planning-scene)))
       (when scene (setq rstate (send scene :robot_state))))

     (when end-coords ;; cds is target coords of end-coords
       (let ((rcds (send self :get-group-tip-coords confkey)))
         (send tgt-cds :transform
               (send (send (send* robot end-coords) :worldcoords)
                     :transformation rcds))))

     (setq tgt-cds (send self :worldcoords->default-frame-relative tgt-cds))

     (let* ((msg (ros::coords->tf-pose-stamped tgt-cds frame-id))
            (req (instance moveit_msgs::GetPositionIKRequest :init
                           :ik_request
                           (instance moveit_msgs::PositionIKRequest :init
                                     :group_name group-name
                                     :avoid_collisions avoid-collision
                                     :constraints (if constraints constraints
                                                    (instance moveit_msgs::constraints :init))
                                     :robot_state (if rstate rstate
                                                    (instance moveit_msgs::RobotState :init))
                                     :attempts (if attempts attempts 0)
                                     :timeout (ros::time timeout)
                                     :pose_stamped msg)))
            (res (ros::service-call "/compute_ik" req)))
       (when (and retry (/= (send res :error_code :val) 1))
         (send req :ik_request :attempts (if attemps (* 2 attemps) 2))
         (send req :ik_request :timeout (ros::time (* 2 timeout)))
         (setq res (ros::service-call "/compute_ik" req)))
       (cond
        ((= (send res :error_code :val) 1) ;; success
         ;; have to do apply multi-dof-joint ...
         (apply-joint_state (send res :solution :joint_state) robot))
        (t
         (warn ";; ik error at ~A~%"
               (assoc (send res :error_code :val) *moveit-error-code-list*))
         (return-from :get-ik-for-pose nil)))
       (send robot :angle-vector)
       )))
  (:execute-trajectory
   (msg &optional (wait nil))
   (let ((req (instance moveit_msgs::ExecuteKnownTrajectoryRequest :init
                        :trajectory msg)))
     (send req :wait_for_execution wait)
     (ros::service-call execute-service req)
     ;; parse req
     ))
  (:motion-plan
   (confkey &key (scene)
            (group-name (cdr (assoc :group-name (cdr (assoc confkey config-list)))))
            (joint-list (cdr (assoc :joint-list (cdr (assoc confkey config-list)))))
            (planning-attempts 1) (planning-time 5.0) (tolerance-below 0.001) (tolerance-above 0.001)
            (workspace-x 1.0) (workspace-y 1.0) (workspace-z 1.0) &allow-other-keys
            )
   (let ((mpr (instance moveit_msgs::motionplanrequest :init))
         res)
     ;;
     (unless scene
       (setq scene (send self :get-planning-scene)))

     (send mpr :workspace_parameters :header :stamp (ros::time-now))
     (send mpr :workspace_parameters :header :frame_id multi-dof-frame);;
     ;;
     (send mpr :workspace_parameters :max_corner :x workspace-x)
     (send mpr :workspace_parameters :max_corner :y workspace-y)
     (send mpr :workspace_parameters :max_corner :z workspace-z)
     (send mpr :workspace_parameters :min_corner :x (- workspace-x))
     (send mpr :workspace_parameters :min_corner :y (- workspace-y))
     (send mpr :workspace_parameters :min_corner :z (- workspace-z))
     ;;
     (send mpr :start_state (send scene :robot_state))

     (send mpr :goal_constraints
      (list
       (instance moveit_msgs::constraints :init :name ""
                 :joint_constraints
                 (mapcar #'(lambda (jn)
                             (instance moveit_msgs::jointconstraint :init
                                       :joint_name (send jn :name)
                                       :position (send jn :ros-joint-angle)
                                       :tolerance_above tolerance-above
                                       :tolerance_below tolerance-below
                                       :weight 1.0))
                         joint-list))))

     (send mpr :planner_id "") ;; ??
     (send mpr :group_name group-name)
     (send mpr :num_planning_attempts planning-attempts)
     (send mpr :allowed_planning_time planning-time)
     (setq res
           (ros::service-call planning-service
                              (instance moveit_msgs::GetMotionPlanRequest
                                        :init :motion_plan_request mpr)))
     (cond
      ((= (send res :motion_plan_response :error_code :val) 1) ;; success
       ;; have to do apply multi-dof-joint ...
       (send res :motion_plan_response))
      (t
       (warn ";; motion plan error at ~A~%"
             (assoc (send res :motion_plan_response :error_code :val)
                    *moveit-error-code-list*))
       (return-from :motion-plan nil)))
     ))
  (:move-arm-to-goal (confkey &rest args &key (wait) &allow-other-keys)
   (let ((ret (send* self :motion-plan args)))
     (when ret
       (send self :execute-trajectory (send ret :trajectory) :wait wait))))
  (:planning-make-trajectory
   (confkey &key (set-angle-vector) (scene) (use-scene t) (planning-time 5.0)
            (planning-attemps 3) (retry) &allow-other-keys)
   (let (ret)
     (if set-angle-vector (send robot :angle-vector set-angle-vector))
     (unless scene (setq scene (send self :get-planning-scene)))
     (setq ret
           (send self :motion-plan confkey
                 :planning-time planning-time :planning-attemps planning-attemps
                 :scene (if use-scene scene)))
     (when (and retry (not ret)) ;; retry
       (when get-scene (setq scene (send self :get-planning-scene)))
       (setq ret
             (send self :motion-plan confkey
                   :planning-time (* 2 planning-time)
                   :planning-attemps (* 2 planning-attemps)
                   :scene (if use-scene scene))))
     ret
     ))
  (:planning-make-trajectory-to-coords
   (cds confkey &key (end-coords) ;; (list :rarm :end-coords)
        (planning-time 5.0) (scene) (frame-id default-frame-id)
        (planning-attemps 3) (retry) (use-scene t)
        &allow-other-keys)
   (let (ret)
     (unless scene (setq scene (send self :get-planning-scene)))
     (unless (send self :get-ik-for-pose cds confkey :end-coords end-coords
                   :use-actual-seed t :retry retry :frame-id frame-id :scene scene)
       (return-from :planning-make-trajectory-to-coords nil))
     (send self :planning-make-trajectory confkey
           :planning-time planning-time :planning-attemps planning-attemps
           :use-scene use-scene :scene scene :retry retry)
     ))
  (:planning-move-arm
   (confkey &key (set-angle-vector) (scene) (use-scene t) (planning-time 5.0)
            (planning-attemps 3) (retry) (wait t) &allow-other-keys)
   (let (ret)
     (if set-angle-vector (send robot :angle-vector set-angle-vector))
     (unless scene (setq scene (send self :get-planning-scene)))
     (setq ret
           (send self :move-arm-to-goal confkey :scene (if use-scene scene)
                 :planning-attemps planning-attemps
                 :planning-time planning-time :wait wait))
     (when (and retry (not ret)) ;; retry
       (if scene (setq scene (send self :get-planning-scene))) ;; override scene
       (setq ret
             (send self :move-arm-to-goal confkey :scene (if use-scene scene)
                   :planning-attemps (* 2 planning-attemps)
                   :planning-time (* 2 planning-time) :wait wait))
       )
     ret
     ))
  (:planning-move-arm-to-coords
   (cds confkey &key (end-coords) ;; (list :rarm :end-coords)
        (planning-time 5.0) (scene) (frame-id default-frame-id)
        (planning-attemps 3) (retry) (use-scene t) (wait t)
        &allow-other-keys)
   (let (ret)
     (unless scene (setq scene (send self :get-planning-scene)))
     (unless (send self :get-ik-for-pose cds confkey :end-coords end-coords
                   :use-actual-seed t :retry retry :frame-id frame-id :scene scene)
       (return-from :planning-move-arm-to-coords nil))
     (send self :planning-move-arm confkey
           :planning-time planning-time :planning-attemps planning-attemps
           :use-scene use-scene :wait wait :scene scene)
     ))
  )

(defun worldcoords->link-relative (wcds &key ((:link lname) "ROOT") (robot *pr2*))
  (let ((base (send robot (intern (string-upcase lname) *keyword-package*))))
    (send (send base :worldcoords) :transformation
          (send wcds :worldcoords))))

(defmethod robot-interface
  (:set-moveit-environment (&optional mv-env)
   (when mv-env (setf (get self :moveit-environment) mv-env))
   (get self :moveit-environment))
  (:planning-environment (&rest args)
   (let ((env (get self :moveit-environment)))
     (when env (forward-message-to env args))))
  (:parse-end-coords (arm use-torso)
   (let (confkey ed-lst)
     (cond
      ((eq arm :rarm)
       (setq confkey (if use-torso :rarm-torso :rarm))
       (setq  ed-lst (list :rarm :end-coords)))
      (t
       (setq confkey (if use-torso :larm-torso :larm))
       (setq  ed-lst (list :larm :end-coords))))
     (cons confkey ed-lst)))
  (:collision-aware-ik
   (cds &rest args &key (move-arm :larm) (use-torso) &allow-other-keys)
   (let* ((r (send self :parse-end-coords move-arm use-torso))
          (confkey (car r))
          (ed-lst (cdr r))
          ret)
     (setq ret
           (send* self :planning-environment
                  :get-ik-for-pose cds confkey :end-coords ed-lst args))
     ret))
  (:angle-vector-make-trajectory
   (av &rest args &key (move-arm :larm) (use-torso) &allow-other-keys)
   (let* ((r (send self :parse-end-coords move-arm use-torso))
          (confkey (car r))
          (ed-lst (cdr r))
          ret)
     (setq ret
           (send* self :planning-environment
                  :planning-make-trajectory confkey
                  :set-angle-vector av :end-coords ed-lst args))
     ret))
  (:end-coords-make-trajectory
   (cds &rest args &key (move-arm :larm) (use-torso) &allow-other-keys)
   (let* ((r (send self :parse-end-coords move-arm use-torso))
          (confkey (car r))
          (ed-lst (cdr r))
          ret)
     (setq ret
             (send* self :planning-environment
                    :planning-make-trajectory-to-coords
                    cds confkey :end-coords ed-lst args))
     ret))
  (:angle-vector-motion-plan ;;
   (av &rest args &key (move-arm :larm) (reset-total-time 5000.0) &allow-other-keys)
   (let (traj ret)
     (setq ret (send* self :angle-vector-make-trajectory av args))
     (when ret
       (setq traj (send ret :trajectory :joint_trajectory))
       (when (< (send (send (car (last (send traj :points))) :time_from_start) :to-sec) 0.001)
         (unless reset-total-time
           (ros::ros-error "Trajectory has very short duration")
           (return-from :angle-vector-motion-plan nil))
         (ros::ros-warn "reset Trajectory Total time")
         (setq traj (send self :trajectory-filter traj :total-time reset-total-time)))
       (send* self :joint-trajectory-to-angle-vector-list move-arm traj args)
       )))
  (:move-end-coords-plan ;;
   (cds &rest args &key (move-arm :larm) (reset-total-time 5000.0) &allow-other-keys)
   (let (traj ret)
     (setq ret (send* self :end-coords-make-trajectory cds args))
     (when ret
       (setq traj (send ret :trajectory :joint_trajectory))
       (when (< (send (send (car (last (send traj :points))) :time_from_start) :to-sec) 0.001)
         (unless reset-total-time
           (ros::ros-error "Trajectory has very short duration")
           (return-from :angle-vector-motion-plan nil))
         (ros::ros-warn "reset Trajectory Total time")
         (setq traj (send self :trajectory-filter traj :total-time reset-total-time)))
       (send* self :joint-trajectory-to-angle-vector-list move-arm traj args)
       )))
  (:trajectory-filter ;; simple trajectory for zero duration
   (traj &key (copy) (total-time 5000.0) (minimum-time 0.001))
   (when (and minimum-time
              (> (send (send (car (last (send traj :points))) :time_from_start) :to-sec)
                 minimum-time))
     (return-from :trajectory-filter traj))
   (when copy
     (setq traj (copy-object traj)))
   (let* ((points (send traj :points))
          (size (length points))
          (time-step (/ 1 (float (1- size))))
          (cntr 0))
     (dolist (pt points)
       (send pt :time_from_start (ros::time (* (/ total-time 1000) cntr time-step)))
       (incf cntr))
     traj))
  )