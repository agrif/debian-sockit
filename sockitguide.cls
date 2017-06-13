\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{sockitguide}[2017/06/13 v1 sockitguide]
\PassOptionsToClass{\CurrentOption}{name}
\LoadClass[nofootinbib,amsmath,amssymb,aps,pra,reprint]{revtex4-1}

\RequirePackage[english]{babel}
\RequirePackage{microtype}
\RequirePackage{hyperref}
\RequirePackage[binary-units]{siunitx}
\RequirePackage[nameinlink]{cleveref}
\RequirePackage{minted}
\RequirePackage{graphicx}
\RequirePackage{menukeys}

\usemintedstyle{bw}
\setminted{autogobble,breakindent=2em,breaksymbolleft={}}

\newcommand\fnurl[2]{%
  \href{#2}{#1}\footnote{\url{#2}}%
}

\newcommand\sockittitle[1]{
  %\preprint{Preprint Number}
  \title{#1}
  %\thanks{A footnote to the article title}
  
  \author{Aaron Griffith}
  \affiliation{Department of Physics, The Ohio State University, Columbus, Ohio, 43210, USA}
  \email{griffith.637@osu.edu}

  %\author{Daniel J. Gauthier}
  %\affiliation{Department of Physics, The Ohio State University, Columbus, Ohio, 43210, USA}
  %\affiliation{Department of Physics, Duke University, Durham, North Carolina 27708, USA}
  
  \date{\today}
  
  %\begin{abstract}
  %\end{abstract}
  
  %\pacs{Valid PACS appear here}
  \maketitle
}
