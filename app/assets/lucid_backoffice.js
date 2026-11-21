document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll("[data-lb-reason-form]").forEach(function (form) {
    var reason = form.querySelector("[data-lb-reason]");
    var submit = form.querySelector("[data-lb-submit]");
    var minimum = parseInt(reason.getAttribute("minlength"), 10) || 0;
    var sync = function () { submit.disabled = reason.value.trim().length < minimum; };
    reason.addEventListener("input", sync);
    reason.addEventListener("blur", sync);
    sync();
  });
});
