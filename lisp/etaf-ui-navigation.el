;;; etaf-ui-navigation.el --- Navigation and disclosure Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Tabs, Accordion and Breadcrumb compose ordinary Buttons and flow layout.
;; They keep navigation state in caller-owned refs and do not create a second
;; focus or event system.

;;; Code:

(require 'etaf-ui-basic)

(defun etaf-ui--navigation-items (items component)
  "Validate navigation ITEMS for COMPONENT and return them unchanged."
  (etaf-check-prop :items items (proper-list-p items)
                   "a list of item plists" component)
  (let (keys labels)
    (dolist (item items)
      (etaf-check-prop :items item
                       (and (proper-list-p item)
                            (plist-get item :key)
                            (stringp (plist-get item :label))
                            (not (string-empty-p (plist-get item :label)))
                            (not (member (plist-get item :key) keys))
                            (not (member (plist-get item :label) labels)))
                       "unique non-nil :key and nonempty string :label"
                       component)
      (push (plist-get item :key) keys)
      (push (plist-get item :label) labels))
    items))

(etaf-define-component etaf-tabs
    (&key items active on-change (variant 'underline))
  "Render controlled navigation TABS.
ITEMS are plists with unique scalar :key and nonempty string :label. ACTIVE
may be a value or ref; ON-CHANGE receives the selected key."
  :render
  (let* ((items (etaf-ui--navigation-items items 'etaf-tabs))
         (active (etaf-ui--reactive-value active)))
    (etaf-check-prop :active active (cl-some (lambda (item) (equal active (plist-get item :key))) items)
                     "a key present in :items" 'etaf-tabs)
    (etaf-check-prop :on-change on-change (functionp on-change)
                     "a function" 'etaf-tabs)
    (etaf-node 'row (list :class (format "etaf-tabs %s" variant) :role 'tablist
                          :width 'stretch :item-gap '(ch 1))
               (mapcar
                (lambda (item)
                  (let* ((key (plist-get item :key))
                         (selected (equal key active)))
                    (etaf-node 'etaf-button
                               (list :label (if selected
                                                (concat "◆ " (plist-get item :label))
                                              (plist-get item :label))
                                     :variant (if selected 'secondary 'ghost)
                                     :aria-label (plist-get item :label)
                                     :on-press (lambda () (funcall on-change key)))
                               nil)))
                items))))

(etaf-define-component etaf-accordion
    (&key items open on-toggle (multiple t))
  "Render disclosure ITEMS controlled by OPEN keys.
Each item has :key, :label and :content. Content may be a string or a
zero-argument function returning a View. MULTIPLE permits more than one open
section; ON-TOGGLE receives the next list of keys."
  :validate
  (progn
    (etaf-ui--navigation-items items 'etaf-accordion)
    (etaf-check-prop :multiple multiple (booleanp multiple) "a boolean" 'etaf-accordion)
    (etaf-check-prop :on-toggle on-toggle (functionp on-toggle)
                     "a function" 'etaf-accordion))
  :render
  (let* ((items (etaf-ui--navigation-items items 'etaf-accordion))
         (open (etaf-ui--reactive-value open)))
    (etaf-check-prop :open open
                     (and (proper-list-p open)
                          (cl-every (lambda (key)
                                     (cl-some (lambda (item) (equal key (plist-get item :key))) items))
                                    open)
                          (or multiple (<= (length open) 1)))
                     "a list of item keys" 'etaf-accordion)
    (etaf-node 'column (list :class "etaf-accordion" :width 'stretch
                             :item-gap '(lh 0))
               (cl-mapcan
                (lambda (item)
                  (let* ((key (plist-get item :key))
                         (expanded (member key open))
                         (content (plist-get item :content)))
                    (etaf-check-prop :content content
                                     (or (stringp content) (functionp content))
                                     "a string or zero-argument function"
                                     'etaf-accordion)
                    (list
                     (etaf-node 'etaf-button
                                (list :label (concat (if expanded "▾ " "▸ ")
                                                     (plist-get item :label))
                                      :variant 'ghost
                                      :on-press
                                      (lambda ()
                                        (funcall on-toggle
                                                 (if expanded
                                                     (delete key (copy-sequence open))
                                                   (if multiple
                                                       (cons key (copy-sequence open))
                                                     (list key))))))
                                nil)
                     (when expanded
                       (if (functionp content)
                           (funcall content)
                         (etaf-node 'etaf-label (list :text content) nil))))))
                items))))

(etaf-define-component etaf-breadcrumb (&key items on-select)
  "Render a breadcrumb trail from string ITEMS.
ON-SELECT, when supplied, receives the zero-based item index."
  :validate
  (progn
    (etaf-check-prop :items items (and (proper-list-p items) items)
                     "a nonempty list of strings" 'etaf-breadcrumb)
    (dolist (item items)
      (etaf-check-prop :items item (stringp item) "strings" 'etaf-breadcrumb))
    (etaf-check-prop :on-select on-select (or (null on-select) (functionp on-select))
                     "a function or nil" 'etaf-breadcrumb))
  :render
  (etaf-node 'row (list :class "etaf-breadcrumb" :width 'stretch
                        :item-gap '(ch 1))
             (cl-loop for item in items for index from 0 append
                      (let ((selected-index index))
                       (list (if on-select
                                (etaf-node 'etaf-button
                                           (list :label item :variant 'ghost
                                                 :on-press
                                                 (lambda ()
                                                   (funcall on-select selected-index)))
                                           nil)
                              (etaf-node 'etaf-label (list :text item) nil))
                            (unless (= index (1- (length items)))
                              (etaf-node 'etaf-label
                                         (list :text "/" :variant 'muted) nil)))))))

(etaf-define-component etaf-steps (&key items current on-change)
  "Render ordered STEPS with a caller-owned CURRENT key."
  :validate
  (progn
    (etaf-ui--navigation-items items 'etaf-steps)
    (etaf-check-prop :on-change on-change (or (null on-change) (functionp on-change))
                     "a function or nil" 'etaf-steps))
  :render
  (let ((current (etaf-ui--reactive-value current)))
    (etaf-check-prop :current current
                     (cl-some (lambda (item) (equal current (plist-get item :key))) items)
                     "a key present in :items" 'etaf-steps)
    (etaf-view
     (flex :class "etaf-steps" :width 'stretch :column-gap '(ch 1)
           :row-gap '(lh 1) :flex-wrap 'wrap :align-items 'center
       (expr
        (cl-loop for item in items for index from 1 append
                 (let* ((key (plist-get item :key))
                        (caption (plist-get item :label))
                        (label (format "%d  %s" index caption))
                        (active (equal key current)))
                   (list (etaf-view
                          (etaf-button :label label :aria-label caption
                                       :variant (if active 'secondary 'ghost)
                                       :on-press (and on-change
                                                      (lambda () (funcall on-change key)))))
                         (when (< index (length items))
                           (etaf-view (etaf-label :text "→" :variant 'muted)))))))))))

(provide 'etaf-ui-navigation)
;;; etaf-ui-navigation.el ends here
