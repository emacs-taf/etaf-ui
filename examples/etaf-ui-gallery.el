;;; etaf-ui-gallery.el --- Atelier, a composed UI workspace -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; M-x etaf-ui-gallery-open opens Atelier. Project actions, release checklist,
;; preferences and floating surfaces share caller-owned state and one Theme.
;; All displayed project data is demonstration content, not benchmark results.

;;; Code:
(require 'etaf-ui)

(defconst etaf-ui-gallery-palette
  '(:ui-fg "#E8EDF8" :ui-bg "#172136" :ui-border "#33435E"
    :ui-muted-fg "#A6B5CE" :ui-progress-track "#2C3A53"
    :ui-success-fg "#A7E8BB" :ui-success-bg "#203E34" :ui-success-border "#4F7564"
    :ui-warning-fg "#F6C879" :ui-warning-bg "#473923" :ui-warning-border "#82693C"
    :ui-danger-fg "#F3A8C9" :ui-danger-bg "#482B40" :ui-danger-border "#895570"
    :ui-info-fg "#8DE1E4" :ui-info-bg "#1D3945" :ui-info-border "#456F7C"
    :ui-button-primary-fg "#241B40" :ui-button-primary-bg "#BBA9FF"
    :ui-button-primary-border "#BBA9FF"
    :ui-button-secondary-fg "#E8EDF8" :ui-button-secondary-bg "#30405C"
    :ui-button-secondary-border "#30405C"
    :ui-button-ghost-fg "#C4CFE3" :ui-button-ghost-bg "#172136"
    :ui-button-ghost-border "#172136"
    :ui-disabled-fg "#A3AEC2" :ui-disabled-bg "#243048"
    :ui-disabled-border "#243048"
    :ui-checkbox-enabled-fg "#E8EDF8" :ui-checkbox-enabled-bg "#24354A"
    :ui-checkbox-enabled-border "#24354A"
    :ui-checkbox-disabled-fg "#A3AEC2" :ui-checkbox-disabled-bg "#243048"
    :ui-checkbox-disabled-border "#243048"
    :ui-selection-enabled-fg "#C4CFE3" :ui-selection-enabled-bg "#1D2A42"
    :ui-selection-enabled-border "#33435E"
    :ui-selection-selected-fg "#241B40" :ui-selection-selected-bg "#BBA9FF"
    :ui-selection-selected-border "#BBA9FF"
    :ui-selection-disabled-fg "#A3AEC2" :ui-selection-disabled-bg "#243048"
    :ui-selection-disabled-border "#243048"
    :ui-panel-fg "#E8EDF8" :ui-panel-bg "#172136" :ui-panel-border "#33435E"
    :ui-table-border "#33435E" :ui-table-selected-fg "#EAE1FF"
    :ui-table-selected-bg "#35304D" :ui-pagination-muted-fg "#A6B5CE")
  "Atelier's semantic palette, scoped to this application by ETAF Context.")

(etaf-define-component etaf-ui-gallery-project (&key name category status accent on-open)
  "Compose an independently reusable project card from the public catalog."
  :view
  (column :padding '((lh 1) (ch 2)) :background-color "#172136"
          :border-top accent :item-gap '(lh 1)
    (etaf-label :text category :variant 'muted)
    (etaf-label :text name :variant 'heading)
    (flex :column-gap '(ch 1) :flex-wrap 'wrap :align-items 'center
      (etaf-badge :text status :variant 'info)
      (etaf-button :label "Open project →" :variant 'ghost :on-press on-open))))

(etaf-define-component etaf-ui-gallery-example ()
  :bindings ((page (etaf-ref 'workspace))
             (help (etaf-ref nil)) (profile (etaf-ref nil))
             (notice (etaf-ref nil)) (dialog (etaf-ref nil))
             (alert-visible (etaf-ref t))
             (workspace (etaf-ref "Atelier Studio"))
             (project-name (etaf-ref "Untitled project"))
             (project-type (etaf-ref 'brand))
             (notifications (etaf-ref t)) (capacity (etaf-ref 6))
             (density (etaf-ref 'cozy)) (zoom (etaf-ref 80))
             (reviewed (etaf-ref nil))
             (open-sections (etaf-ref '(brief)))
             (activity (etaf-ref "Your workspace is up to date.")))
  :setup (etaf-theme-provide etaf-ui-gallery-palette)
  :view
  (column :id "gallery-root" :width '(vw 100) :height '(vh 100)
          :overflow 'scroll :cross-align 'center :background-color "#0B1020"
          :color "#E8EDF8"
    (column :width '(min (ch 132) (% 100)) :box-sizing 'border-box
            :padding '((lh 1) (ch 3)) :item-gap '(lh 1)
      (flex :justify-content 'space-between :align-items 'center
            :column-gap '(ch 2) :flex-wrap 'wrap
        (column
          (box :font-weight 'bold :color "#BBA9FF" "A T E L I E R   /   0 1")
          (etaf-label :text "A workspace for things worth making." :variant 'muted))
        (row :item-gap '(ch 1)
          (etaf-button :ref 'gallery-help :id "gallery-help" :label "Quick help"
                       :variant 'ghost :on-press (lambda () (setf (etaf-value help) t)))
          (etaf-button :ref 'gallery-profile :id "gallery-profile" :label "GK · Studio"
                       :variant 'secondary :on-press (lambda () (setf (etaf-value profile) t)))))
      (flex :justify-content 'space-between :align-items 'center
            :flex-wrap 'wrap :gap '((lh 1) (ch 2))
        (etaf-tabs :width 'max-content
                   :items '((:key workspace :label "Workspace")
                            (:key library :label "Component library")
                            (:key settings :label "Preferences"))
                   :active page :on-change (lambda (key) (setf (etaf-value page) key)))
        (row :item-gap '(ch 1)
          (etaf-dropdown-menu
           :label "Actions"
           :items '((:key create :label "New project")
                    (:key refresh :label "Refresh workspace")
                    (:key archive :label "Archive studio" :disabled t))
           :on-select (lambda (key)
                        (pcase key
                          ('create (setf (etaf-value dialog) t))
                          ('refresh (setf (etaf-value activity) "Workspace refreshed."
                                          (etaf-value notice) t)))))
          (etaf-button :ref 'gallery-notify :id "gallery-notify" :label "Activity"
                       :variant 'ghost :on-press (lambda () (setf (etaf-value notice) t)))
          (etaf-button :ref 'gallery-new :label "+ New project"
                       :on-press (lambda () (setf (etaf-value dialog) t)))))
      (expr
       (pcase (etaf-value page)
         ('workspace
          (etaf-view
           (column :item-gap '(lh 1)
             (grid :grid-template-columns '((fr 2) (fr 1))
                   :gap '((lh 1) (ch 2))
               (column :background-color "#26223B" :padding '((lh 1) (ch 2))
                       :item-gap '(lh 1)
                 (box :font-weight 'bold :color "#BBA9FF" "FEATURED COLLECTION / SPRING 026")
                 (box :font-weight 'bold :color "#F5F0FF" "Make space for the unexpected.")
                 (box :height '(lh 4) :overflow 'hidden
                   (box :position 'absolute :left '(ch 0) :top '(lh 1)
                        :width '(ch 15) :height '(lh 3) :text-align 'center
                        :background-color "#7561AC" :color "#F5F0FF" "\nFORM / 01")
                   (box :position 'absolute :left '(ch 12) :top '(lh 0)
                        :width '(ch 15) :height '(lh 3) :z-index 1 :text-align 'center
                        :background-color "#BBA9FF" :color "#241B40" "\nSPACE / 02")
                   (box :position 'absolute :left '(ch 24) :top '(lh 1)
                        :width '(ch 15) :height '(lh 3) :z-index 2 :text-align 'center
                        :background-color "#D8EAAB" :color "#303D22" "\nPLAY / 03"))
                 (etaf-label :text "Small ideas, connected into something bigger."
                             :color "#D6CDEF"))
               (etaf-panel :title "Release checklist"
                 (etaf-label :text "ORBIT / DESIGN SYSTEM" :variant 'muted)
                 (etaf-label :text "✓  Tokens & typography" :variant 'success)
                 (etaf-label :text "✓  Layout & components" :variant 'success)
                 (etaf-checkbox :bind reviewed :label "Review interactions")
                 (etaf-progress :value (if (etaf-value reviewed) 3 2) :max 3
                                :label "Ready to share")
                 (etaf-label :text "One shared state, from input to feedback." :variant 'muted)))
             (grid :grid-template-columns '((fr 1) (fr 1) (fr 1))
                   :gap '((lh 1) (ch 2))
               (etaf-ui-gallery-project :name "Orbit" :category "01 / BRAND SYSTEM"
                 :status "In review" :accent "#BBA9FF"
                 :on-open (lambda () (setf (etaf-value project-name) "Orbit"
                                          (etaf-value dialog) t)))
               (etaf-ui-gallery-project :name "Relay" :category "02 / PRODUCT LAUNCH"
                 :status "In progress" :accent "#8DE1E4"
                 :on-open (lambda () (setf (etaf-value project-name) "Relay"
                                          (etaf-value dialog) t)))
               (etaf-ui-gallery-project :name "Mosaic" :category "03 / STUDIO NOTES"
                 :status "Exploring" :accent "#F6C879"
                 :on-open (lambda () (setf (etaf-value project-name) "Mosaic"
                                          (etaf-value dialog) t))))
             (grid :grid-template-columns '((fr 2) (fr 1))
                   :gap '((lh 1) (ch 2))
               (etaf-panel :title "Recent work"
                 (etaf-table
                  :columns '((:key :name :label "Deliverable" :width (fr 2))
                             (:key :owner :label "Owner" :width (fr 1))
                             (:key :status :label "Status" :width (fr 1)))
                  :rows '((:id 1 :name "Identity guidelines" :owner "Mina" :status "Review")
                          (:id 2 :name "Launch page" :owner "Theo" :status "Draft")
                          (:id 3 :name "Motion studies" :owner "Aya" :status "Ready"))
                  :row-key (lambda (row) (plist-get row :id))))
               (etaf-panel :title "Project notes"
                 (etaf-accordion
                  :items '((:key brief :label "Creative brief"
                             :content "Keep it clear. Leave room to play.")
                           (:key materials :label "Materials"
                             :content "Type, colour and reusable components.")
                           (:key delivery :label "Delivery"
                             :content "Review together, then share the result."))
                  :open open-sections :multiple nil
                  :on-toggle (lambda (keys) (setf (etaf-value open-sections) keys))))))))
         ('library
          (etaf-view
           (column :item-gap '(lh 1)
             (etaf-breadcrumb :items '("Atelier" "Library" "Building blocks"))
             (expr
              (when (etaf-value alert-visible)
                (etaf-view
                 (etaf-alert :title "A small vocabulary. Endless compositions."
                             :message "These are the same components used throughout this workspace."
                             :dismissible t :on-dismiss
                             (lambda () (setf (etaf-value alert-visible) nil))))))
             (grid :grid-template-columns '((fr 1) (fr 1)) :gap '((lh 1) (ch 2))
               (etaf-panel :title "Signals & status"
                 (row :item-gap '(ch 1)
                   (etaf-badge :text "Ready" :variant 'success)
                   (etaf-badge :text "Review" :variant 'warning)
                   (etaf-badge :text "Blocked" :variant 'danger))
                 (etaf-divider :label "Collection")
                 (etaf-statistic :label "Reusable patterns" :value "12" :trend "+3 this week")
                 (etaf-progress :value 8 :max 12 :label "Published"))
               (etaf-panel :title "Empty & loading states"
                 (etaf-empty :title "A fresh canvas" :description "Your next collection starts here."
                             :action-label "Create collection"
                             :on-action (lambda () (setf (etaf-value dialog) t)))
                 (etaf-skeleton :height '(lh 1))
                 (etaf-skeleton :width '(% 65) :height '(lh 1)))
               (etaf-panel :title "Selection controls"
                 (etaf-radio :bind density :label "Density"
                             :options '((compact . "Compact") (cozy . "Cozy") (airy . "Airy")))
                 (etaf-segmented :bind project-type
                                 :options '((brand . "Brand") (product . "Product") (notes . "Notes")))
                 (etaf-switch :bind notifications :label "Live notifications")
                 (etaf-slider :bind zoom :label "Preview zoom" :min 40 :max 120 :step 10))
               (etaf-panel :title "Composition patterns"
                 (etaf-card :title "A reusable card" :description "Surfaces compose ordinary content.")
                 (row :item-gap '(ch 1)
                   (etaf-avatar :name "Mina" :variant 'info)
                   (etaf-avatar :name "Theo" :variant 'success)
                   (etaf-avatar :name "Aya" :variant 'warning))
                 (etaf-timeline
                  :items '((:key one :title "Brief shaped" :content "A clear direction." :status "Now")
                           (:key two :title "System connected" :content "Reusable pieces align." :status "Next"))))))))
         ('settings
          (etaf-view
           (grid :grid-template-columns '((fr 2) (fr 1)) :gap '((lh 1) (ch 2))
             (etaf-panel :title "Studio preferences"
               (etaf-label :text "Make this space yours." :variant 'muted)
               (etaf-input :type 'text :bind workspace :label "Studio name")
               (etaf-input :type 'number :bind capacity :label "Project capacity" :min 1 :max 24)
               (etaf-switch :bind notifications :label "Live notifications")
               (etaf-segmented :bind density
                               :options '((compact . "Compact") (cozy . "Cozy") (airy . "Airy")))
               (etaf-slider :bind zoom :label "Preview zoom" :min 40 :max 120 :step 10)
               (etaf-button :label "Save preferences" :on-press
                            (lambda () (setf (etaf-value activity) "Preferences saved."
                                             (etaf-value notice) t))))
             (etaf-panel :title "Your workspace"
               (etaf-label :text workspace :variant 'heading)
               (etaf-label :text "Local by design. Ready to compose." :variant 'muted)
               (etaf-badge :text "Personal studio" :variant 'info)))))))
      (flex :justify-content 'space-between :flex-wrap 'wrap :column-gap '(ch 2)
        (etaf-label :text activity :variant 'muted)
        (etaf-label :text "ETAF UI  /  Interactive demo workspace" :variant 'muted))
      (etaf-tooltip :open help :anchor "gallery-help" :placement 'bottom-start
                    :text "Tab to explore · Enter to act · Escape to close."
                    :on-close (lambda () (setf (etaf-value help) nil)))
      (etaf-popover :open profile :anchor "gallery-profile" :placement 'bottom-end
                    :title "Your studio" :on-close (lambda () (setf (etaf-value profile) nil))
        (etaf-label :text workspace :variant 'strong)
        (etaf-label :text "Personal workspace / local" :variant 'muted)
        (etaf-button :label "Manage preferences" :variant 'ghost :on-press
                     (lambda () (setf (etaf-value profile) nil (etaf-value page) 'settings))))
      (etaf-toast :open notice :anchor "gallery-notify" :title "Studio activity"
                  :message activity :variant 'success
                  :on-close (lambda () (setf (etaf-value notice) nil)))
      (etaf-dialog :open dialog :title "Make something new" :close-label "Cancel"
                   :on-close (lambda () (setf (etaf-value dialog) nil))
        (etaf-label :text "Give your next idea a home." :variant 'muted)
        (etaf-input :type 'text :bind project-name :label "Project name")
        (etaf-select :bind project-type :label "Collection"
                     :options '((brand . "Brand system") (product . "Product") (notes . "Studio notes")))
        (etaf-button :label "Create project" :on-press
                     (lambda () (setf (etaf-value dialog) nil
                                      (etaf-value activity)
                                      (format "Created %s." (etaf-value project-name))
                                      (etaf-value notice) t)))))))

;;;###autoload
(defun etaf-ui-gallery-open ()
  "Mount the integrated catalog Gallery; interactive calls display its buffer."
  (interactive)
  (let ((buffer (etaf-mount "*ETAF UI Gallery*" (etaf-view (etaf-ui-gallery-example)))))
    (when (called-interactively-p 'interactive) (switch-to-buffer buffer))
    buffer))

(provide 'etaf-ui-gallery)
;;; etaf-ui-gallery.el ends here
