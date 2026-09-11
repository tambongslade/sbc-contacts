function setLang(l){
  document.documentElement.lang=l;
  document.querySelectorAll('.langbar button').forEach(function(b){b.classList.toggle('active',b.dataset.l===l)});
  try{localStorage.setItem('lang',l)}catch(e){}
}
document.addEventListener('DOMContentLoaded',function(){
  document.querySelectorAll('.langbar button[data-l]').forEach(function(b){
    b.addEventListener('click',function(){setLang(b.dataset.l)});
  });
  var s;try{s=localStorage.getItem('lang')}catch(e){}
  var d=s||((navigator.language||'fr').toLowerCase().indexOf('en')===0?'en':'fr');
  setLang(d);
  var y=document.getElementById('y');if(y)y.textContent=new Date().getFullYear();
});
