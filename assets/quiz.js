/* Reusable retrieval-practice quiz widget */
(function () {
  function initQuiz(container) {
    const cards = Array.from(container.querySelectorAll(".quiz-card"));
    const scoreEl = container.querySelector("[data-quiz-score]");
    const resetBtn = container.querySelector("[data-quiz-reset]");
    let answered = 0;
    let correct = 0;

    function updateScore() {
      if (!scoreEl) return;
      scoreEl.textContent = `Score: ${correct} / ${cards.length} (${answered} answered)`;
    }

    cards.forEach((card) => {
      const options = Array.from(card.querySelectorAll(".quiz-opt"));
      const feedback = card.querySelector(".quiz-feedback");
      const explanation = card.dataset.explanation || "";

      options.forEach((btn) => {
        btn.addEventListener("click", () => {
          if (card.dataset.done === "1") return;
          card.dataset.done = "1";
          answered += 1;

          const isRight = btn.dataset.correct === "true";
          options.forEach((b) => {
            b.disabled = true;
            if (b.dataset.correct === "true") b.classList.add("is-correct");
          });

          if (isRight) {
            correct += 1;
            feedback.className = "quiz-feedback visible ok";
            feedback.innerHTML = `<strong>Correct.</strong> ${explanation}`;
          } else {
            btn.classList.add("is-wrong");
            feedback.className = "quiz-feedback visible err";
            feedback.innerHTML = `<strong>Not quite.</strong> ${explanation}`;
          }
          updateScore();
        });
      });
    });

    if (resetBtn) {
      resetBtn.addEventListener("click", () => {
        answered = 0;
        correct = 0;
        cards.forEach((card) => {
          delete card.dataset.done;
          card.querySelectorAll(".quiz-opt").forEach((b) => {
            b.disabled = false;
            b.classList.remove("is-correct", "is-wrong");
          });
          const feedback = card.querySelector(".quiz-feedback");
          feedback.className = "quiz-feedback";
          feedback.textContent = "";
        });
        updateScore();
      });
    }

    updateScore();
  }

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-quiz]").forEach(initQuiz);
  });
})();
