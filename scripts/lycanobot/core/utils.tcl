# Small useful functions
namespace eval ::utils {

   # Escaping chars
   proc filt {data} {
      return [regsub -all {\W} $data {\\&}]
   }

   # intersection of 2 lists
   proc lintersect {list1 list2 {option -exact}} {
      if {$option ne "-nocase"} { set option -exact }
      return [lmap x $list1 {expr {[lsearch $option $list2 $x] >= 0 ? $x : [continue]}}]
   }

   # diff between 2 lists
   proc ldiff {list1 list2 {option -exact}} {
      if {$option ne "-nocase"} { set option -exact }
      return [lmap x $list1 {expr {[lsearch $option $list2 $x] < 0 ? $x : [continue]}}]
   }

   # Removes an element from a list
   proc lremove {datas needle {option -exact}} {
      if {$option ne "-nocase"} { set option -exact }
      return [lsearch -all -inline -not $option $datas $needle]
   }
   
   # Replace an element in a list (case sensitive)
   proc lreplace {datas needle {replacement ""}} {
      if {$needle eq ""} { return $datas }
      if {$replacement eq ""} {
         return [[namespace current]::lremove $datas $needle]
      }
      set idx [lsearch $datas $needle]
      if {$idx > -1} {
         return [::lreplace $datas $idx $idx $replacement]
      } else {
         return $datas
      }
   }
   
   # Replace an element in a list (case insensitive)
   proc lireplace {datas needle {replacement ""}} {
      if {$needle eq ""} { return $datas }
      if {$replacement eq ""} {
         return [[namespace current]::lremove $datas $needle -nocase]
      }
      set idx [lsearch -nocase $datas $needle]
      if {$idx > -1} {
         return [::lreplace $datas $idx $idx $replacement]
      } else {
         return $datas
      }
   }
   
   # Generate a random key
   proc randKey {{len 8}} {
      set chars {a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9}
      set key ""
      while {[string length $key] < $len} {
         append key [lindex $chars [rand [llength $chars]]]
      }
      return $key
   }

}