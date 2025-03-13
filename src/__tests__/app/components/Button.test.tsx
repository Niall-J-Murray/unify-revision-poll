import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import Button from "../../../app/components/Button";

describe("Button Component", () => {
  it("renders children correctly", () => {
    render(<Button onClick={() => {}}>Test Button</Button>);
    expect(screen.getByText("Test Button")).toBeInTheDocument();
  });

  it("calls onClick handler when clicked", () => {
    const handleClick = jest.fn();
    render(<Button onClick={handleClick}>Click Me</Button>);

    const button = screen.getByText("Click Me");
    fireEvent.click(button);

    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it("applies custom className", () => {
    render(
      <Button onClick={() => {}} className="custom-class">
        Custom Button
      </Button>
    );

    const button = screen.getByText("Custom Button");
    expect(button).toHaveClass("custom-class");
  });

  it("applies disabled state correctly", () => {
    render(
      <Button onClick={() => {}} disabled>
        Disabled Button
      </Button>
    );

    const button = screen.getByText("Disabled Button");
    expect(button).toBeDisabled();
    expect(button).toHaveClass("opacity-50");
    expect(button).toHaveClass("cursor-not-allowed");
  });

  it("does not call onClick when disabled", () => {
    const handleClick = jest.fn();
    render(
      <Button onClick={handleClick} disabled>
        Disabled
      </Button>
    );

    const button = screen.getByText("Disabled");
    fireEvent.click(button);

    expect(handleClick).not.toHaveBeenCalled();
  });

  it("renders with border when not disabled", () => {
    render(<Button onClick={() => {}}>Bordered Button</Button>);

    const button = screen.getByText("Bordered Button");
    expect(button).toHaveClass("border");
    expect(button).toHaveClass("border-yellow-500");
  });

  it("does not have border when disabled", () => {
    render(
      <Button onClick={() => {}} disabled>
        No Border Button
      </Button>
    );

    const button = screen.getByText("No Border Button");
    expect(button).not.toHaveClass("border");
    expect(button).not.toHaveClass("border-yellow-500");
  });
});
