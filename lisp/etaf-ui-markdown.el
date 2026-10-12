;;; etaf-ui-markdown.el --- Markdown document rendering for etaf-ui -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Markdown document rendering shared by ETAF applications.  The functions
;; turn the block tree of `etaf-ui-markdown-parse' into ordinary ETAF Views:
;; headings, paragraphs, lists, blockquote callouts, pipe tables, fenced code
;; blocks, footnotes and inline emphasis, code, links and media placeholders.
;; Presentation is data-driven: every color comes from the caller's `:palette'
;; alist, and media and code blocks go through caller callbacks, so one
;; renderer serves a previewer, a manual reader or any other document view.
;;
;; The renderer owns no state and no buffer; it is a pure function of a block
;; tree plus an environment plist, which makes it usable for headless tests and
;; inside a mounted Component alike.  See `etaf-ui-markdown-view-block' and
;; `etaf-ui-markdown-view-blocks' for the environment contract.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'etaf)
(require 'etaf-ui-basic)
(require 'etaf-ui-feedback)
(require 'etaf-ui-markdown-parse)


;;; ---------------------------------------------------------------------------

(defun etaf-ui-markdown--env-color (env key)
  "Return ENV's color for semantic KEY.
ENV carries a `:palette' alist of semantic color keys; a missing palette or an
unknown key signals `etaf-ui-markdown-error'."
  (let ((palette (plist-get env :palette)))
    (unless palette
      (signal 'etaf-ui-markdown-error
              (list "Markdown rendering requires a :palette")))
    (or (cdr (assq key palette))
        (signal 'etaf-ui-markdown-error
                (list (format "Unknown markdown color: %S" key))))))

(defun etaf-ui-markdown--mono-family ()
  "Return the family of the frame's fixed-pitch font, or nil.
A frame whose fixed-pitch face inherits the default family yields nil, and
code spans then use the frame's own font instead of guessing a family."
  (let ((family (face-attribute 'fixed-pitch :family nil t)))
    (and (stringp family) (not (string-empty-p family)) family)))

(defun etaf-ui-markdown--base-pixels ()
  "Return the frame's default font size in CSS reference pixels."
  (let ((height (face-attribute 'default :height nil t)))
    (if (numberp height)
        (max 8 (round (/ (* height 4.0) 30.0)))
      16.0)))

(defun etaf-ui-markdown--heading-pixels (level)
  "Return the heading font size for LEVEL."
  (let ((base (etaf-ui-markdown--base-pixels)))
    (round (pcase level
             (1 (* base 1.55))
             (2 (* base 1.32))
             (3 (* base 1.14))
             (_ base)))))

(defun etaf-ui-markdown--divider (&optional label)
  "Return a horizontal divider View, optionally labeled."
  (etaf-node 'etaf-divider (list :orientation 'horizontal :label label) nil))

(defun etaf-ui-markdown--spacer (&optional lines)
  "Return an empty spacer Box LINES lines tall."
  (etaf-node 'box (list :height (list 'lh (or lines 1))) nil))


(defun etaf-ui-markdown--run-props (run env)
  "Return the ETAF style props of inline RUN in ENV."
  (let ((props nil))
    (when (plist-get run :bold)
      (setq props (plist-put props :font-weight 'bold)))
    (when (plist-get run :italic)
      (setq props (plist-put props :font-style 'italic)))
    (when (plist-get run :strike)
      (setq props (plist-put props :text-decoration-line '(line-through))))
    (when (plist-get run :code)
      (setq props (plist-put props :background-color
                             (etaf-ui-markdown--env-color env :panel)))
      (let ((mono (etaf-ui-markdown--mono-family)))
        (when mono (setq props (plist-put props :font-family mono)))))
    (when (plist-get run :link)
      (setq props (plist-put props :color (etaf-ui-markdown--env-color env :accent)))
      (setq props (plist-put props :text-decoration-line '(underline))))
    (when (plist-get run :muted)
      (setq props (plist-put props :color (etaf-ui-markdown--env-color env :muted))))
    props))

(defun etaf-ui-markdown--flatten-inlines (nodes inherited env)
  "Return styled run entries for inline NODES in ENV.
INHERITED is the style attribute plist of the enclosing inline element.
Entries are (:text STRING :props PLIST) or (:view VIEW)."
  (let (result)
    (dolist (node nodes)
      (pcase (plist-get node :type)
        ('text
         (push (list :text (or (plist-get node :text) "") :props inherited) result))
        ('break
         (push (list :text (if (plist-get node :hard) "\n" " ") :props inherited)
               result))
        ('code
         (push (list :text (or (plist-get node :text) "")
                     :props (plist-put (copy-sequence inherited) :code t))
               result))
        ((or 'emph 'strong 'strike)
         (let ((child (copy-sequence inherited)))
           (when (eq (plist-get node :type) 'emph)
             (setq child (plist-put child :italic t)))
           (when (eq (plist-get node :type) 'strong)
             (setq child (plist-put child :bold t)))
           (when (eq (plist-get node :type) 'strike)
             (setq child (plist-put child :strike t)))
           (setq result
                 (append (nreverse
                          (etaf-ui-markdown--flatten-inlines
                           (plist-get node :children) child env))
                         result))))
        ((or 'link 'autolink)
         (let ((child (plist-put (copy-sequence inherited) :link (plist-get node :url))))
           (setq result
                 (append (nreverse
                          (etaf-ui-markdown--flatten-inlines
                           (plist-get node :children) child env))
                         result))))
        ('footnote-ref
         (push (list :view (etaf-ui-markdown--footnote-view node env)) result))
        ('image
         (push (list :view (etaf-ui-markdown--render-media 'inline-image node env))
               result))
        ('html
         (push (list :text (or (plist-get node :text) "")
                     :props (plist-put (copy-sequence inherited) :muted t))
               result))
        (_ nil)))
    (nreverse result)))

(defun etaf-ui-markdown--inline-runs (inlines env base)
  "Flatten INLINES into styled runs for ENV.
BASE is the plist of style attributes inherited from the enclosing block.
Adjacent text runs with equal styles are merged into one entry."
  (let ((runs nil))
    (dolist (run (etaf-ui-markdown--flatten-inlines inlines base env))
      (let* ((previous (car runs))
             (text (plist-get run :text))
             (props (plist-get run :props))
             (merge (and previous
                         (not (plist-get previous :view))
                         (not (plist-get run :view))
                         (plist-get previous :text)
                         (equal (plist-get previous :props) props)
                         (not (string-suffix-p "\n" (plist-get previous :text)))
                         (not (string-prefix-p "\n" text)))))
        (if merge
            (setcar runs (plist-put previous :text
                                    (concat (plist-get previous :text) text)))
          (push run runs))))
    (nreverse runs)))

(defun etaf-ui-markdown--render-media (kind node env)
  "Render media NODE of KIND through ENV's `:render-media', or a placeholder.
KIND is `image' for a block image, `video' for a block video, `inline-image'
for an inline image and `html-media' for a source-bearing HTML media element.
NODE is the parsed inline or a media descriptor.  Without `:render-media' the
renderer keeps the document text: the media's alt text or URL."
  (if-let* ((renderer (plist-get env :render-media)))
      (funcall renderer kind node env)
    (etaf-node 'text
               (list :color (etaf-ui-markdown--env-color env :muted))
               (list (format "[%s]" (or (plist-get node :alt)
                                         (plist-get node :url)
                                         "media"))))))

(defun etaf-ui-markdown--runs-view (inlines env base &optional extra)
  "Return ETAF children for INLINES in ENV.
BASE is a run-attribute plist (`:bold', `:italic', `:strike', `:code',
`:link', `:muted'); EXTRA is an Ebox style plist applied to every text run."
  (let ((nodes nil))
    (dolist (run (etaf-ui-markdown--inline-runs inlines env base))
      (if-let* ((view (plist-get run :view)))
          (push view nodes)
        (let* ((attributes (plist-get run :props))
               (text (plist-get run :text))
               (props (let ((merged (copy-sequence extra))
                            (inline (etaf-ui-markdown--run-props attributes env)))
                        ;; Heading typography supplies defaults; an inline
                        ;; link or code span overrides only its own properties.
                        (while inline
                          (setq merged (plist-put merged (pop inline) (pop inline))))
                        merged))
               (url (plist-get attributes :link))
               (props (if url
                          (append props
                                  (list :role 'link :tab-index 0 :help-echo url
                                        :on-press (when-let* ((open (plist-get env :open-link)))
                                                    (lambda () (funcall open url)))))
                        props)))
          (push (etaf-node 'text props (list text)) nodes))))
    (nreverse nodes)))

(defun etaf-ui-markdown--footnote-view (node env)
  "Return the superscript reference View of footnote NODE in ENV."
  (let ((number (or (plist-get node :number)
                    (plist-get node :label)))
        (label (plist-get node :label)))
    (etaf-node 'text
               (append
                (list :color (etaf-ui-markdown--env-color env :accent))
                (unless (plist-get env :line-grid)
                  (list :font-size (round (* (etaf-ui-markdown--base-pixels) 0.8))))
                (list :role 'link :tab-index 0
                     :help-echo (format "Footnote %s" label)
                     :on-press (lambda ()
                                 (when-let* ((jump (plist-get env :footnote-jump)))
                                   (funcall jump label)))))
               (list (format "[%s]" number)))))

(defun etaf-ui-markdown--paragraph-node (block env)
  "Return the paragraph View of BLOCK in ENV.
A paragraph that contains only one image delegates to ENV's `:render-media'."
  (if (and (= 1 (length (plist-get block :children)))
           (eq (plist-get (car (plist-get block :children)) :type) 'image))
      (let ((image (car (plist-get block :children))))
        (etaf-ui-markdown--render-media 'image image env))
    (etaf-node 'box
               (list :width 'stretch :wrap-mode 'word)
               (etaf-ui-markdown--runs-view (plist-get block :children) env nil))))

(defun etaf-ui-markdown--heading-node (block env)
  "Return the heading View of BLOCK in ENV.
With ENV's `:line-grid' the heading keeps the body font size, so its line
has the standard height; the level then shows through color and, for level
2, an accent bar drawn as a left border that occupies no line."
  (let* ((level (plist-get block :level))
         (grid (plist-get env :line-grid))
         (color (cond ((>= level 5) (etaf-ui-markdown--env-color env :muted))
                      ((and grid (= level 1))
                       (etaf-ui-markdown--env-color env :accent))
                      (t (etaf-ui-markdown--env-color env :heading))))
         (children
          (etaf-ui-markdown--runs-view
           (plist-get block :children) env (list :bold t)
           (append (unless grid
                     (list :font-size (etaf-ui-markdown--heading-pixels level)))
                   (list :color color)))))
    (etaf-node 'box
               (append
                (list :id (plist-get block :id)
                      :width 'stretch
                      ;; Headings carry no margin or rule of their own: the
                      ;; block flow separates every sibling with exactly one
                      ;; blank line, including heading-to-heading.
                      :margin '((lh 0) (ch 0)))
                (when (and grid (= level 2))
                  (list :border-left
                        (list '(px 3) 'solid
                              (etaf-ui-markdown--env-color env :accent))
                        :padding-left '(ch 1))))
               children)))

(defun etaf-ui-markdown--code-block-node (block env)
  "Return the code block View of BLOCK in ENV.
ENV's `:render-code-block', when present, may return a View for the block;
nil keeps the default fenced block."
  (or (when-let* ((renderer (plist-get env :render-code-block)))
        (funcall renderer block env))
      (etaf-ui-markdown--default-code-block-node block env)))

(defun etaf-ui-markdown--default-code-block-node (block env)
  "Return the default fenced code block View of BLOCK in ENV."
  (let* ((mono (etaf-ui-markdown--mono-family))
         (lang (plist-get block :lang))
         (body (etaf-node 'box
                          (list :width 'stretch :wrap-mode 'char
                                :font-family mono
                                :color (etaf-ui-markdown--env-color env :ink))
                          (list (etaf-node 'text nil
                                           (list (plist-get block :text))))))
         (header (when lang
                   (etaf-node 'flex
                              (list :width 'stretch :justify-content 'flex-end)
                              (list (etaf-node 'etaf-tag
                                               (list :text lang :variant 'neutral)
                                               nil))))))
    (etaf-node 'box
               (list :width 'stretch
                     :background-color (etaf-ui-markdown--env-color env :panel)
                     :border (list '(px 1) 'solid (etaf-ui-markdown--env-color env :border))
                     :padding-top (if header '(lh 0) '(lh 1))
                     :padding-bottom '(lh 1)
                     :padding-left '(ch 2)
                     :padding-right '(ch 2))
               (append (when header (list header)) (list body)))))

(defun etaf-ui-markdown--blockquote-node (block env)
  "Return the blockquote View of BLOCK in ENV.
A GitHub alert (`> [!NOTE]' and friends) becomes a tinted callout; any other
quote keeps the muted surface and the accent bar."
  (let* ((children (plist-get block :children))
         (alert (and (plist-get (plist-get env :features) :alerts)
                     (etaf-ui-markdown--alert-kind children env))))
    (if alert
        (let* ((spec (etaf-ui-markdown--alert-spec alert env))
               (color (etaf-ui-markdown--env-color env (nth 1 spec)))
               (soft (etaf-ui-markdown--env-color env (nth 2 spec))))
          (etaf-node 'box
                     (list :width 'stretch
                           :background-color soft
                           :border-left (list '(px 3) 'solid color)
                           :padding-top '(lh 0)
                           :padding-bottom '(lh 0)
                           :padding-left '(ch 2)
                           :padding-right '(ch 2))
                     (append
                      (list (etaf-node 'text
                                       (list :color color :font-weight 'bold)
                                       (list (format "%s %s" (nth 3 spec) (nth 0 spec)))))
                      (etaf-ui-markdown-view-blocks
                       (etaf-ui-markdown--alert-blocks children) env t))))
      (etaf-node 'box
                 (list :width 'stretch
                       :background-color (etaf-ui-markdown--env-color env :quote-bg)
                       :border-left (list '(px 3) 'solid
                                          (etaf-ui-markdown--env-color env :quote-bar))
                       :padding-top '(lh 0)
                       :padding-bottom '(lh 1)
                       :padding-left '(ch 2)
                       :padding-right '(ch 2))
                 (etaf-ui-markdown-view-blocks children env t)))))

(defun etaf-ui-markdown--alert-kind (blocks env)
  "Return the GitHub alert kind when BLOCKS open with an alert marker."
  (let* ((first (car blocks))
         (children (and first (eq (plist-get first :type) 'paragraph)
                        (plist-get first :children)))
         (text (and children (eq (plist-get (car children) :type) 'text)
                    (plist-get (car children) :text))))
    (when (and text (string-match "\\`\\[!\\([A-Za-z]+\\)\\][ \t]*\\(?:\n\\|\\'\\)" text))
      (let ((kind (downcase (match-string 1 text))))
        (and (etaf-ui-markdown--alert-spec kind env) kind)))))
(defconst etaf-ui-markdown--alert-defaults
  '((note "Note" :accent :accent-soft "ℹ")
    (tip "Tip" :ok :ok-soft "✔")
    (important "Important" :important :important-soft "★")
    (warning "Warning" :warn :warn-soft "⚠")
    (caution "Caution" :danger :danger-soft "⛔"))
  "GitHub alert kinds with their default label, color keys and icon.")

(defun etaf-ui-markdown--alert-spec (kind env)
  "Return (LABEL COLOR-KEY SOFT-KEY ICON) for alert KIND in ENV, or nil.
ENV's `:alert-labels' alist may override the labels of
`etaf-ui-markdown--alert-defaults'."
  (let* ((name (intern (downcase kind)))
         (spec (cdr (assq name etaf-ui-markdown--alert-defaults))))
    (when spec
      (if-let* ((label (cdr (assq name (plist-get env :alert-labels)))))
          (cons label (cdr spec))
        spec))))

(defun etaf-ui-markdown--alert-blocks (blocks)
  "Return BLOCKS with the leading alert marker removed.
The document tree is shared across renders, so the first paragraph is rebuilt
instead of mutated."
  (let* ((first (car blocks))
         (children (plist-get first :children))
         (text (plist-get (car children) :text))
         (rest (replace-regexp-in-string
                "\\`\\[![A-Za-z]+\\][ \t]*\\n?" "" text)))
    (cons (let ((paragraph (copy-sequence first)))
            (plist-put paragraph :children
                       (if (string-empty-p rest)
                           (cdr children)
                         (cons (plist-put (copy-sequence (car children)) :text rest)
                               (cdr children)))))
          (cdr blocks))))

(defun etaf-ui-markdown--inline-width (inlines)
  "Return the display width of the text of INLINES and their children."
  (let ((width 0))
    (dolist (node inlines)
      (setq width (+ width
                     (string-width (or (plist-get node :text) ""))
                     (etaf-ui-markdown--inline-width
                      (plist-get node :children)))))
    width))

(defun etaf-ui-markdown--table-tracks (rows columns)
  "Return the grid tracks of COLUMNS for table ROWS.
Each column's fraction follows its widest cell, bounded so a short column
keeps a readable minimum and one long column cannot starve the others."
  (let ((widths (make-list columns 0)))
    (dolist (row rows)
      (cl-loop for inlines in row
               for column from 0
               do (setf (nth column widths)
                        (max (nth column widths)
                             (etaf-ui-markdown--inline-width inlines)))))
    (mapcar (lambda (width) (list 'fr (max 4 (min 32 width)))) widths)))

(defun etaf-ui-markdown--table-node (block env)
  "Return the table View of BLOCK in ENV.
The table draws its own grid: an outer border, a row separator, a column
separator, a tinted header row and zebra striping, so every column and
alignment stays visible at a glance.  Columns share the width in proportion
to their content, and cells wrap at word boundaries."
  (let* ((aligns (plist-get block :aligns))
         (columns (length aligns))
         (rows (append (list (plist-get block :header))
                       (plist-get block :rows)))
         (tracks (etaf-ui-markdown--table-tracks rows columns))
         (last-row (1- (length rows)))
         (border (list '(px 1) 'solid (etaf-ui-markdown--env-color env :border)))
         (grids nil))
    (cl-loop for row in rows
             for row-index from 0
             do (let ((cells nil))
                  (cl-loop for inlines in row
                           for align in aligns
                           for column-index from 0
                           do (push
                               (etaf-node 'box
                                          (list :padding '((lh 0) (ch 1))
                                                :width 'stretch
                                                :overflow 'hidden
                                                :wrap-mode 'word
                                                :text-align (or align 'left)
                                                :border-bottom (and (/= row-index last-row)
                                                                    border)
                                                :border-right (and (/= column-index
                                                                       (1- columns))
                                                                   border)
                                                :background-color
                                                (cond
                                                 ((zerop row-index)
                                                  (etaf-ui-markdown--env-color env :table-header))
                                                 ((zerop (% row-index 2))
                                                  (etaf-ui-markdown--env-color env :table-stripe))
                                                 (t nil)))
                                          (etaf-ui-markdown--runs-view
                                           inlines env
                                           (when (zerop row-index) (list :bold t))))
                               cells))
                  ;; One grid per row keeps every row's columns aligned by the
                  ;; same fractional tracks while staying within the layouts
                  ;; the native renderer can accelerate.
                  (push (etaf-node 'grid
                                   (list :width 'stretch
                                         :grid-template-columns tracks)
                                   (nreverse cells))
                        grids)))
    (etaf-node 'box
               (list :width 'stretch :border border)
               (nreverse grids))))

(defun etaf-ui-markdown--thematic-break-node ()
  "Return the thematic break View."
  (etaf-ui-markdown--divider))

(defconst etaf-ui-markdown--html-media-regexp
  "<\\(video\\|img\\)\\b[^>]*>"
  "Opening tags whose source is rendered as a media card.")

(defun etaf-ui-markdown--html-attribute (tag name)
  "Return NAME's attribute value from TAG, or nil."
  (when (string-match (format "%s[ \t]*=[ \t]*[\"']\\([^\"']*\\)[\"']" name) tag)
    (match-string 1 tag)))

(defun etaf-ui-markdown--html-comment-p (text)
  "Return non-nil when TEXT is an HTML comment block.
Comments carry no rendered content, so the renderer drops them instead of
printing markup the document never intended to show."
  (string-prefix-p "<!--" (string-trim text)))

(defun etaf-ui-markdown--html-media (text)
  "Return a media descriptor for raw HTML TEXT, or nil.
A `<video>' or `<img>' opening tag with a source becomes a descriptor with
`:url', `:kind' (`video' or `image') and `:alt'."
  (when (string-match etaf-ui-markdown--html-media-regexp text)
    (let* ((tag (match-string 0 text))
           (src (etaf-ui-markdown--html-attribute tag "src")))
      (when src
        (list :type 'html-media
              :url src
              :kind (if (string-match-p "\\`<video" tag) 'video 'image)
              :alt (or (etaf-ui-markdown--html-attribute tag "alt")
                       (etaf-ui-markdown--html-attribute tag "title")))))))

(defun etaf-ui-markdown--html-block-node (block env)
  "Return the View of raw HTML BLOCK in ENV, or nil.
HTML comments render as nothing; a media element goes through ENV's
`:render-media'; other tags stay visible as code, so the renderer never
silently drops content it cannot render."
  (let* ((text (plist-get block :text))
         (media (and (not (etaf-ui-markdown--html-comment-p text))
                     (etaf-ui-markdown--html-media text))))
    (cond
     ((etaf-ui-markdown--html-comment-p text) nil)
     (media (etaf-ui-markdown--render-media (plist-get media :kind) media env))
     (t (etaf-ui-markdown--html-code-node text env)))))

(defun etaf-ui-markdown--html-code-node (text env)
  "Return a muted monospace block View for raw HTML TEXT in ENV."
  (etaf-node 'box
             (list :width 'stretch :wrap-mode 'char
                   :background-color (etaf-ui-markdown--env-color env :panel)
                   :padding-top '(lh 1)
                   :padding-bottom '(lh 1)
                   :padding-left '(ch 2)
                   :padding-right '(ch 2))
             (list (etaf-node 'text
                              (list :color (etaf-ui-markdown--env-color env :muted))
                              (list text)))))

(defun etaf-ui-markdown--list-node (block env)
  "Return the list View of BLOCK in ENV."
  (let ((tight (plist-get block :tight))
        (ordered (plist-get block :ordered))
        (start (or (plist-get block :start) 1))
        (index 0)
        (items nil))
    (dolist (item (plist-get block :items))
      (cl-incf index)
      (let* ((checked (plist-get item :checked))
             (task (plist-get item :task))
             (marker
              (cond
               (task (etaf-node 'text
                                (list :color (if checked
                                                 (etaf-ui-markdown--env-color env :accent)
                                               (etaf-ui-markdown--env-color env :muted)))
                                (list (if checked "☑" "☐"))))
               (ordered (etaf-node 'text
                                   (list :color (etaf-ui-markdown--env-color env :muted))
                                   (list (format "%d." (+ start (1- index))))))
               (t (etaf-node 'text
                             (list :color (etaf-ui-markdown--env-color env :muted))
                             (list "•")))))
             (content (etaf-ui-markdown-view-blocks (plist-get item :children) env tight)))
        (push (etaf-node 'flex
                         (list :width 'stretch)
                         (list
                          (etaf-node 'box
                                     (list :width '(ch 3) :flex-shrink 0)
                                     (list marker))
                          (etaf-node 'column
                                     (list :width 'stretch :min-width '(ch 0))
                                     content)))
              items)))
    (etaf-node 'column
               (list :width 'stretch
                     :item-gap (list 'lh (if tight 0 1)))
               (nreverse items))))

(defun etaf-ui-markdown--footnote-def-node (block env)
  "Return the footnote definition View of BLOCK in ENV."
  (etaf-node 'box
             (list :width 'stretch :wrap-mode 'word
                   :id (format "footnote-%s" (plist-get block :label)))
             (append
              (list (etaf-node 'text
                               (list :color (etaf-ui-markdown--env-color env :accent)
                                     :font-weight 'bold)
                               (list (format "[%s] " (plist-get block :number)))))
              (etaf-ui-markdown--runs-view
               (cl-loop for child in (plist-get block :children)
                        append (if (eq (plist-get child :type) 'paragraph)
                                   (plist-get child :children)
                                 nil))
               env nil))))

(defun etaf-ui-markdown--view-block (block env)
  "Return the list of Views for one BLOCK in ENV."
  (pcase (plist-get block :type)
    ('heading (list (etaf-ui-markdown--heading-node block env)))
    ('paragraph (list (etaf-ui-markdown--paragraph-node block env)))
    ('code-block (list (etaf-ui-markdown--code-block-node block env)))
    ('blockquote (list (etaf-ui-markdown--blockquote-node block env)))
    ('list (list (etaf-ui-markdown--list-node block env)))
    ('table (list (etaf-ui-markdown--table-node block env)))
    ('thematic-break (list (etaf-ui-markdown--thematic-break-node)))
    ('html-block
     (when-let* ((node (etaf-ui-markdown--html-block-node block env)))
       (list node)))
    ('footnote-def (list (etaf-ui-markdown--footnote-def-node block env)))
    (_ nil)))

(defun etaf-ui-markdown-view-block (block env)
  "Return BLOCK rendered as one ETAF View, or nil when nothing renders.
A block that expands to several Views is wrapped in one column, so callers
own one node per block for references, spacing or scrolling."
  (let ((views (etaf-ui-markdown--view-block block env)))
    (cond
     ((null views) nil)
     ((null (cdr views)) (car views))
     (t (etaf-node 'column (list :width 'stretch :item-gap '(lh 0)) views)))))

(defun etaf-ui-markdown-view-blocks (blocks env &optional tight)
  "Return the list of Views for BLOCKS in ENV, in document order.
Every block is rendered by `etaf-ui-markdown--view-block'; consecutive blocks
are separated by one blank line, unless TIGHT drops it for nested content.
The list preserves the document order, so callers may wrap each View in their
own container for scrolling, selection or per-block references."
  (let ((nodes nil)
        (first t))
    (dolist (block blocks)
      (when-let* ((views (etaf-ui-markdown--view-block block env)))
        (unless (or first tight)
          (push (etaf-ui-markdown--spacer) nodes))
        (setq first nil)
        (dolist (view views)
          (when view (push view nodes)))))
    (nreverse nodes)))

(provide 'etaf-ui-markdown)
;;; etaf-ui-markdown.el ends here
