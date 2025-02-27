import Button from "@/app/components/Button";

export default function AnotherPage() {
  const handleClick = () => {
    // Add your click handler logic here
    console.log("Button clicked");
  };

  return (
    <Button onClick={handleClick} className="bg-blue-500 text-white">
      Click Me
    </Button>
  );
}
