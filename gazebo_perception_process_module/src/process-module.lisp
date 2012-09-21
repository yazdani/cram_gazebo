;;; Copyright (c) 2012, Jan Winkler <winkler@cs.uni-bremen.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of Willow Garage, Inc. nor the names of its
;;;       contributors may be used to endorse or promote products derived from
;;;       this software without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :gazebo-perception-process-module)

(defclass perceived-object (object-designator-data) ())
(defclass handle-perceived-object (object-designator-data) ())

(defmethod designator-pose ((designator object-designator))
  (object-pose (reference designator)))

(defmethod designator-distance ((designator-1 object-designator)
                                      (designator-2 object-designator))
  (cl-transforms:v-dist (cl-transforms:origin (designator-pose designator-1))
                        (cl-transforms:origin (designator-pose designator-2))))

(defgeneric make-new-desig-description (old-desig perceived-object)
  (:documentation "Merges the description of `old-desig' with the
properties of `perceived-object'")
  (:method ((old-desig object-designator) (po object-designator-data))
    (let ((obj-loc-desig (make-designator 'location
					  `((pose ,(object-pose po))))))
      (cons `(at ,obj-loc-desig)
            (remove 'at (description old-desig) :key #'car)))))

(defun make-handled-object-designator (&key object-type
                                            object-pose
                                            handles
                                            name)
  "Creates and returns an object designator with object type
`object-type' and object pose `object-pose' and attaches location
designators according to handle information in `handles'."
  (let ((combined-description (append `((type ,object-type)
                                        (name ,name)
                                        (at ,(make-designator
                                              'location
					      `((pose ,object-pose)))))
                                      `,(make-handle-designator-sequence
					 handles))))
    (make-designator 'object combined-description)))

(defun make-handle-designator-sequence (handles)
  "Converts the sequence `handles' (handle-pose handle-radius) into a
sequence of object designators representing handle objects. Each
handle object then consist of a location designator describing its
relative position as well as the handle's radius for grasping
purposes."
  (mapcar (lambda (handle-desc)
            `(handle
              ,(make-designator 'object
                                `((at ,(make-designator
					'location
					`((pose ,(first handle-desc)))))
                                  (radius ,(second handle-desc))
                                  (type handle)))))
          handles))

(defun find-object (name)
  "Finds the object named `name' in the gazebo world and returns an
instance of PERCEIVED-OBJECT."
  (let ((model-pose (get-model-pose name :test #'object-names-equal)))
    (when model-pose
      (make-instance 'perceived-object
        :pose model-pose
        :object-identifier name))))

(defmethod make-new-desig-description ((old-desig object-designator)
                                       (perceived-object perceived-object))
  (let ((description (call-next-method)))
    (if (member 'name description :key #'car)
        description
        (cons `(name ,(object-identifier perceived-object)) description))))

(defun perceived-object->designator (designator perceived-object)
  (make-effective-designator
   designator
   :new-properties (make-new-desig-description designator perceived-object)
   :data-object perceived-object))

(defun find-with-designator (designator)
  ;; Since gazebo does not provide object types and we do not have a
  ;; knowledge base for that yet.
  ;;
  ;; TODO(moesenle): add verification of location using the AT
  ;; property.
  ;;
  ;; TODO(winkler): Read object properties from simple-knowledge and
  ;; equip the object designator with those properties.
  (with-desig-props (name) designator
    (let ((perceived-object (find-object name)))
      (if perceived-object
          (perceived-object->designator designator perceived-object)
          (fail 'object-not-found :object-desig designator)))))

(defun emit-perception-event (designator)
  (cram-plan-knowledge:on-event (make-instance 'cram-plan-knowledge:object-perceived-event
                                  :perception-source :gazebo-perception-process-module
                                  :object-designator designator))
  designator)

(def-process-module gazebo-perception-process-module (input)
  (assert (typep input 'action-designator))
  (let ((object-designator (reference input)))
    (ros-info (gazebo-perception-process-module process-module)
	      "Searching for object ~a" object-designator)
    (let ((result (find-with-designator object-designator)))
      (ros-info (gazebo-perception-process-module process-module)
		"Found objects: ~a" result)
      (emit-perception-event result)
      (list result))))
